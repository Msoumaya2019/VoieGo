const DEFAULT_LOCATION = { lat: 48.8919, lon: 2.2383 };
const CACHE_SECONDS = 45;

export default {
  async fetch(request, env, context) {
    const url = new URL(request.url);
    const cors = corsHeaders(request, env);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== 'GET') {
      return json({ error: 'Méthode non autorisée.' }, 405, cors);
    }
    if (url.pathname === '/health') {
      return json({ ok: true, service: 'voiego-prim-proxy' }, 200, cors);
    }
    if (url.pathname !== '/api/v1/snapshot' && url.pathname !== '/api/v1/lines') {
      return json({ error: 'Route inconnue.' }, 404, cors);
    }
    if (!env.PRIM_API_KEY) {
      return json({ error: 'PRIM_API_KEY absent du serveur.' }, 503, cors);
    }

    if (url.pathname === '/api/v1/lines') {
      try {
        return await linesResponse(url, request, env, context, cors);
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Erreur PRIM inconnue.';
        return json({ error: message }, 502, cors);
      }
    }

    const lineRef = url.searchParams.get('lineRef');
    if (!/^STIF:Line::C\d+:$/.test(lineRef ?? '')) {
      return json({ error: 'lineRef invalide.' }, 400, cors);
    }
    const location = {
      lat: numberOr(url.searchParams.get('lat'), DEFAULT_LOCATION.lat),
      lon: numberOr(url.searchParams.get('lon'), DEFAULT_LOCATION.lon),
    };
    if (!validLocation(location)) {
      return json({ error: 'Coordonnées invalides.' }, 400, cors);
    }

    const cacheKey = new Request(
      `${url.origin}/cache/snapshot?lineRef=${encodeURIComponent(lineRef)}&lat=${location.lat.toFixed(3)}&lon=${location.lon.toFixed(3)}`,
    );
    const cache = caches.default;
    const cached = await cache.match(cacheKey);
    if (cached) return withCors(cached, cors);

    try {
      const lineId = toNavitiaLineId(lineRef);
      const base = env.PRIM_NAVITIA_BASE || 'https://prim.iledefrance-mobilites.fr/marketplace/v2/navitia';
      const stop = await nearestStop(base, env.PRIM_API_KEY, lineId, location);
      const departurePayload = await primFetch(
        `${base}/stop_areas/${encodeURIComponent(stop.id)}/departures?data_freshness=realtime&count=10&filter=${encodeURIComponent(`line.id=${lineId}`)}`,
        env.PRIM_API_KEY,
      );
      const departures = normalizeDepartures(departurePayload, stop);
      const alert = await trafficAlert(env, lineId);
      const response = json(
        {
          source: 'prim-navitia',
          stop: { id: stop.id, name: stop.name, distanceMeters: stop.distance },
          departures,
          alert,
          generatedAt: new Date().toISOString(),
          attribution: 'Île-de-France Mobilités / PRIM',
        },
        200,
        { ...cors, 'Cache-Control': `public, max-age=${CACHE_SECONDS}` },
      );
      context.waitUntil(cache.put(cacheKey, response.clone()));
      return response;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Erreur PRIM inconnue.';
      return json({ error: message }, 502, cors);
    }
  },
};

async function linesResponse(url, request, env, context, cors) {
  const commercialModes = {
    bus: 'Bus',
    metro: 'Metro',
    rer: 'RER',
    transilien: 'Transilien',
  };
  const mode = url.searchParams.get('mode');
  const commercialMode = commercialModes[mode];
  if (!commercialMode) return json({ error: 'Mode invalide.' }, 400, cors);

  const cacheKey = new Request(`${url.origin}/cache/lines?mode=${mode}`);
  const cache = caches.default;
  const cached = await cache.match(cacheKey);
  if (cached) return withCors(cached, cors);

  const base = env.PRIM_NAVITIA_BASE || 'https://prim.iledefrance-mobilites.fr/marketplace/v2/navitia';
  const filter = `commercial_mode.id=commercial_mode:${commercialMode}`;
  const payload = await primFetch(`${base}/lines?count=100&filter=${encodeURIComponent(filter)}`, env.PRIM_API_KEY);
  const values = Array.isArray(payload.lines) ? payload.lines : [];
  const lines = values
    .filter((line) => /^line:IDFM:C\d+$/.test(line.id || ''))
    .map((line) => ({
      code: line.code || line.name || '?',
      lineRef: `STIF:Line::${line.id.split(':').at(-1)}:`,
      color: `#${line.color || '2A6FBB'}`,
      textColor: `#${line.text_color || 'FFFFFF'}`,
    }))
    .sort((a, b) => a.code.localeCompare(b.code, 'fr', { numeric: true }));
  const response = json(
    { source: 'prim-navitia', lines },
    200,
    { ...cors, 'Cache-Control': 'public, max-age=86400' },
  );
  context.waitUntil(cache.put(cacheKey, response.clone()));
  return response;
}

async function nearestStop(base, apiKey, lineId, location) {
  const coord = `${location.lon};${location.lat}`;
  const params = new URLSearchParams({
    distance: '3000',
    count: '20',
    filter: `line.id=${lineId}`,
  });
  params.append('type[]', 'stop_area');
  const payload = await primFetch(`${base}/coords/${coord}/places_nearby?${params}`, apiKey);
  const places = Array.isArray(payload.places_nearby) ? payload.places_nearby : [];
  const place = places.find((item) => item.stop_area?.id);
  if (!place) throw new Error('Aucun arrêt de cette ligne trouvé à moins de 3 km.');
  return {
    id: place.stop_area.id,
    name: place.stop_area.name || 'Arrêt à proximité',
    distance: Number(place.distance || 0),
  };
}

async function trafficAlert(env, lineId) {
  try {
    const base = env.PRIM_TRAFFIC_BASE || 'https://prim.iledefrance-mobilites.fr/marketplace/v2/navitia/line_reports';
    const payload = await primFetch(
      `${base}/lines/${encodeURIComponent(lineId)}/line_reports?count=20`,
      env.PRIM_API_KEY,
    );
    const disruption = (payload.disruptions || []).find((item) => item.status !== 'past');
    if (!disruption) return null;
    const message = (disruption.messages || []).find((item) => item.channel?.content_type === 'text/plain')?.text;
    return {
      title: disruption.severity?.name || 'Information trafic',
      message: message || disruption.cause || 'Une perturbation est signalée sur cette ligne.',
    };
  } catch (_) {
    return null;
  }
}

async function primFetch(url, apiKey) {
  const response = await fetch(url, {
    headers: { apikey: apiKey, Accept: 'application/json' },
  });
  if (!response.ok) {
    throw new Error(`PRIM a répondu ${response.status}.`);
  }
  return response.json();
}

export function normalizeDepartures(payload, stop) {
  const values = Array.isArray(payload.departures) ? payload.departures : [];
  return values
    .map((item) => {
      const date = item.stop_date_time?.departure_date_time || item.stop_date_time?.arrival_date_time;
      if (!date) return null;
      return {
        destination: item.display_informations?.direction || 'Destination inconnue',
        stopName: item.stop_point?.name || stop.name,
        expectedAt: navitiaDateToIso(date),
        walkingMinutes: Math.max(1, Math.round(Number(stop.distance || 0) / 80)),
        confidence: item.stop_date_time?.data_freshness === 'realtime' ? 'confiance élevée' : 'horaire théorique',
        vehicleJourneyName: item.display_informations?.headsign || null,
      };
    })
    .filter(Boolean);
}

export function navitiaDateToIso(value) {
  const match = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})$/.exec(value);
  if (!match) throw new Error('Date Navitia invalide.');
  const [, year, month, day, hour, minute, second] = match;
  const utcGuess = new Date(Date.UTC(+year, +month - 1, +day, +hour, +minute, +second));
  const zoneName = new Intl.DateTimeFormat('fr-FR', {
    timeZone: 'Europe/Paris',
    timeZoneName: 'longOffset',
  }).formatToParts(utcGuess).find((part) => part.type === 'timeZoneName')?.value;
  const offset = zoneName?.replace('UTC', '') || '+01:00';
  return `${year}-${month}-${day}T${hour}:${minute}:${second}${offset}`;
}

export function toNavitiaLineId(lineRef) {
  const code = /^STIF:Line::(C\d+):$/.exec(lineRef)?.[1];
  if (!code) throw new Error('lineRef invalide.');
  return `line:IDFM:${code}`;
}

function numberOr(value, fallback) {
  if (value == null || value === '') return fallback;
  return Number(value);
}

function validLocation({ lat, lon }) {
  return Number.isFinite(lat) && Number.isFinite(lon) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
}

function corsHeaders(request, env) {
  const requested = request.headers.get('Origin');
  const allowed = env.ALLOWED_ORIGIN || '*';
  const origin = allowed === '*' || requested === allowed ? (requested || '*') : allowed;
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    Vary: 'Origin',
  };
}

function withCors(response, cors) {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(cors)) headers.set(key, value);
  return new Response(response.body, { status: response.status, headers });
}

function json(body, status, headers) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...headers },
  });
}
