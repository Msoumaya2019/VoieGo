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
    const supportedRoutes = new Set([
      '/api/v1/lines',
      '/api/v1/stops',
      '/api/v1/directions',
      '/api/v1/snapshot',
      '/api/v1/nearby',
      '/api/v1/journeys',
      '/api/v1/places',
      '/api/v1/traffic',
    ]);
    if (!supportedRoutes.has(url.pathname)) {
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

    if (url.pathname === '/api/v1/nearby') {
      try {
        return await nearbyResponse(url, request, env, context, cors);
      } catch (error) {
        return proxyErrorResponse(error, cors);
      }
    }

    if (url.pathname === '/api/v1/journeys') {
      try {
        return await journeysResponse(url, env, cors);
      } catch (error) {
        return proxyErrorResponse(error, cors);
      }
    }

    if (url.pathname === '/api/v1/places') {
      try {
        return await placesResponse(url, env, cors);
      } catch (error) {
        return proxyErrorResponse(error, cors);
      }
    }

    if (url.pathname === '/api/v1/traffic') {
      const lineRef = url.searchParams.get('lineRef');
      if (!/^STIF:Line::C\d+:$/.test(lineRef ?? '')) {
        return json({ error: 'lineRef invalide.' }, 400, cors);
      }
      try {
        const alert = await fetchTrafficAlert(env, toNavitiaLineId(lineRef));
        return json(
          {
            source: 'prim-navitia',
            status: alert ? 'disrupted' : 'normal',
            alert,
          },
          200,
          { ...cors, 'Cache-Control': 'public, max-age=60' },
        );
      } catch (error) {
        return proxyErrorResponse(error, cors);
      }
    }

    const lineRef = url.searchParams.get('lineRef');
    if (!/^STIF:Line::C\d+:$/.test(lineRef ?? '')) {
      return json({ error: 'lineRef invalide.' }, 400, cors);
    }
    const lineId = toNavitiaLineId(lineRef);
    if (url.pathname === '/api/v1/stops') {
      try {
        return await stopsResponse(url, request, env, context, cors, lineId);
      } catch (error) {
        return proxyErrorResponse(error, cors);
      }
    }
    if (url.pathname === '/api/v1/directions') {
      try {
        return await directionsResponse(url, request, env, context, cors, lineId);
      } catch (error) {
        return proxyErrorResponse(error, cors);
      }
    }

    const selectedStopId = url.searchParams.get('stopId');
    const selectedRouteId = url.searchParams.get('routeId');
    if (selectedStopId && !validStopId(selectedStopId)) {
      return json({ error: 'stopId invalide.' }, 400, cors);
    }
    if (selectedRouteId && !validRouteId(selectedRouteId)) {
      return json({ error: 'routeId invalide.' }, 400, cors);
    }
    const hasUserLocation = url.searchParams.has('lat') && url.searchParams.has('lon');
    const location = hasUserLocation
      ? {
          lat: Number(url.searchParams.get('lat')),
          lon: Number(url.searchParams.get('lon')),
        }
      : null;
    if (location && !validLocation(location)) {
      return json({ error: 'Coordonnées invalides.' }, 400, cors);
    }

    const cacheKey = new Request(
      `${url.origin}/cache/snapshot?lineRef=${encodeURIComponent(lineRef)}&stopId=${encodeURIComponent(selectedStopId || '')}&routeId=${encodeURIComponent(selectedRouteId || '')}`,
    );
    const cache = caches.default;
    const cached = await cache.match(cacheKey);
    if (cached) return withCors(cached, cors);

    try {
      const base = env.PRIM_NAVITIA_BASE || 'https://prim.iledefrance-mobilites.fr/marketplace/v2/navitia';
      const stop = selectedStopId
        ? { id: selectedStopId, name: 'Arrêt sélectionné', distance: 0, isNearby: false }
        : location
        ? await nearestStop(base, env.PRIM_API_KEY, lineId, location)
        : await referenceStop(base, env.PRIM_API_KEY, lineId);
      const departureFilter = selectedRouteId
        ? `route.id=${selectedRouteId}`
        : `line.id=${lineId}`;
      let departurePayload = await primFetch(
        `${base}/stop_areas/${encodeURIComponent(stop.id)}/departures?data_freshness=realtime&count=20&filter=${encodeURIComponent(departureFilter)}`,
        env.PRIM_API_KEY,
      );
      let departures = normalizeDepartures(departurePayload, stop);
      if (departures.length === 0) {
        departurePayload = await primFetch(
          `${base}/stop_areas/${encodeURIComponent(stop.id)}/departures?count=20&filter=${encodeURIComponent(departureFilter)}`,
          env.PRIM_API_KEY,
        );
        departures = normalizeDepartures(departurePayload, stop);
      }
      const alert = await trafficAlert(env, lineId);
      const response = json(
        {
          source: 'prim-navitia',
          stop: { id: stop.id, name: stop.name, distanceMeters: stop.distance },
          departures,
          alert,
          locationMatched: hasUserLocation && stop.isNearby,
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
      const status = error instanceof ProxyError ? error.status : 502;
      return json({ error: message }, status, cors);
    }
  },
};

async function linesResponse(url, request, env, context, cors) {
  const commercialModes = {
    bus: 'Bus',
    metro: 'Metro',
    rer: 'RapidTransit',
    transilien: 'LocalTrain',
    tramway: 'Tramway',
  };
  const mode = url.searchParams.get('mode');
  const commercialMode = commercialModes[mode];
  if (!commercialMode) return json({ error: 'Mode invalide.' }, 400, cors);

  const cacheKey = new Request(`${url.origin}/cache/v2/lines?mode=${mode}`);
  const cache = caches.default;
  const cached = await cache.match(cacheKey);
  if (cached) return withCors(cached, cors);

  const base = env.PRIM_NAVITIA_BASE || 'https://prim.iledefrance-mobilites.fr/marketplace/v2/navitia';
  const filter = `commercial_mode.id=commercial_mode:${commercialMode}`;
  const values = await fetchAllLines(base, env.PRIM_API_KEY, filter);
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

async function nearbyResponse(url, request, env, context, cors) {
  const location = {
    lat: Number(url.searchParams.get('lat')),
    lon: Number(url.searchParams.get('lon')),
  };
  if (!validLocation(location)) {
    return json({ error: 'Coordonnées invalides.' }, 400, cors);
  }
  const requestedRadius = Number(url.searchParams.get('radius') || 500);
  const radius = Math.min(500, Math.max(100, Math.round(requestedRadius)));
  const cacheKey = new Request(
    `${url.origin}/cache/nearby?lat=${location.lat.toFixed(3)}&lon=${location.lon.toFixed(3)}&radius=${radius}`,
  );
  const cache = caches.default;
  const cached = await cache.match(cacheKey);
  if (cached) return withCors(cached, cors);

  const base = env.PRIM_NAVITIA_BASE || 'https://prim.iledefrance-mobilites.fr/marketplace/v2/navitia';
  const params = new URLSearchParams({ distance: `${radius}`, count: '12' });
  params.append('type[]', 'stop_area');
  const coord = `${location.lon};${location.lat}`;
  const payload = await primFetch(
    `${base}/coords/${coord}/places_nearby?${params}`,
    env.PRIM_API_KEY,
  );
  const nearbyPlaces = (Array.isArray(payload.places_nearby) ? payload.places_nearby : [])
    .filter((place) => place.stop_area?.id)
    .slice(0, 12);
  const stops = await Promise.all(nearbyPlaces.map(async (place) => {
    const stop = place.stop_area;
    let departures = [];
    try {
      departures = await nextStopDepartures(base, env.PRIM_API_KEY, stop.id);
    } catch (_) {
      // L’arrêt reste visible même si ses prochains passages sont indisponibles.
    }
    return {
      id: stop.id,
      name: stop.name || 'Arrêt sans nom',
      distanceMeters: Number(place.distance || 0),
      latitude: Number(stop.coord?.lat),
      longitude: Number(stop.coord?.lon),
      departures,
    };
  }));
  const response = json(
    { source: 'prim-navitia', radiusMeters: radius, stops },
    200,
    { ...cors, 'Cache-Control': 'public, max-age=60' },
  );
  context.waitUntil(cache.put(cacheKey, response.clone()));
  return response;
}

async function nextStopDepartures(base, apiKey, stopId) {
  const payload = await primFetch(
    `${base}/stop_areas/${encodeURIComponent(stopId)}/departures?data_freshness=realtime&count=12`,
    apiKey,
  );
  return (Array.isArray(payload.departures) ? payload.departures : [])
    .map((item) => {
      const date = item.stop_date_time?.departure_date_time ||
        item.stop_date_time?.arrival_date_time;
      if (!date) return null;
      return {
        line: item.display_informations?.code || '?',
        mode: item.display_informations?.commercial_mode || 'Transport',
        destination: item.display_informations?.direction || 'Destination inconnue',
        expectedAt: navitiaDateToIso(date),
        realtime: item.stop_date_time?.data_freshness === 'realtime',
      };
    })
    .filter(Boolean)
    .sort((a, b) => a.expectedAt.localeCompare(b.expectedAt))
    .slice(0, 2);
}

async function journeysResponse(url, env, cors) {
  const fromQuery = (url.searchParams.get('from') || '').trim();
  const toQuery = (url.searchParams.get('to') || '').trim();
  if (fromQuery.length < 3 || toQuery.length < 3 || fromQuery.length > 200 || toQuery.length > 200) {
    return json({ error: 'Renseignez deux adresses valides.' }, 400, cors);
  }

  const base = env.PRIM_NAVITIA_BASE || 'https://prim.iledefrance-mobilites.fr/marketplace/v2/navitia';
  const fromId = validPlaceId(url.searchParams.get('fromId'))
    ? url.searchParams.get('fromId')
    : null;
  const toId = validPlaceId(url.searchParams.get('toId'))
    ? url.searchParams.get('toId')
    : null;
  const fromSessionToken = validGoogleSessionToken(url.searchParams.get('fromSessionToken'))
    ? url.searchParams.get('fromSessionToken')
    : null;
  const toSessionToken = validGoogleSessionToken(url.searchParams.get('toSessionToken'))
    ? url.searchParams.get('toSessionToken')
    : null;
  const [from, to] = await Promise.all([
    fromId
      ? resolveRequestedPlace(fromId, fromQuery, fromSessionToken, env)
      : resolvePlace(base, env.PRIM_API_KEY, fromQuery),
    toId
      ? resolveRequestedPlace(toId, toQuery, toSessionToken, env)
      : resolvePlace(base, env.PRIM_API_KEY, toQuery),
  ]);
  const params = new URLSearchParams({
    from: from.id,
    to: to.id,
    count: '3',
    datetime_represents: 'departure',
  });
  const datetime = url.searchParams.get('datetime');
  if (datetime && /^\d{8}T\d{6}$/.test(datetime)) params.set('datetime', datetime);
  params.append('first_section_mode[]', 'walking');
  params.append('last_section_mode[]', 'walking');
  const payload = await primFetch(`${base}/journeys?${params}`, env.PRIM_API_KEY);
  const journeys = (Array.isArray(payload.journeys) ? payload.journeys : [])
    .filter((journey) => journey.type !== 'non_pt_walk')
    .slice(0, 3)
    .map(normalizeJourney);
  return json(
    { source: 'prim-navitia', from, to, journeys },
    200,
    { ...cors, 'Cache-Control': 'public, max-age=30' },
  );
}

async function placesResponse(url, env, cors) {
  const query = (url.searchParams.get('q') || '').trim();
  if (query.length < 3 || query.length > 120) {
    return json({ error: 'Saisissez au moins trois caractères.' }, 400, cors);
  }
  const sessionToken = validGoogleSessionToken(url.searchParams.get('sessionToken'))
    ? url.searchParams.get('sessionToken')
    : null;
  const base = env.PRIM_NAVITIA_BASE || 'https://prim.iledefrance-mobilites.fr/marketplace/v2/navitia';
  const params = new URLSearchParams({ q: query, count: '7' });
  params.append('type[]', 'stop_area');
  const requests = [primFetch(`${base}/places?${params}`, env.PRIM_API_KEY)];
  if (env.GOOGLE_PLACES_API_KEY) {
    requests.push(fetchGooglePlaceSuggestions(query, sessionToken, env.GOOGLE_PLACES_API_KEY));
  }
  const [primResult, googleResult] = await Promise.allSettled(requests);
  const primPlaces = primResult.status === 'fulfilled'
    ? (Array.isArray(primResult.value.places) ? primResult.value.places : [])
        .filter((place) => place.id && place.stop_area)
        .slice(0, 4)
        .map(normalizePlaceSuggestion)
    : [];
  const googlePlaces = googleResult?.status === 'fulfilled' ? googleResult.value : [];
  if (primPlaces.length === 0 && googlePlaces.length === 0) {
    if (primResult.status === 'rejected') throw primResult.reason;
    if (googleResult?.status === 'rejected') throw googleResult.reason;
  }
  const places = deduplicatePlaceSuggestions([...googlePlaces, ...primPlaces]).slice(0, 8);
  return json({
    source: googlePlaces.length > 0 ? 'google-places+prim-navitia' : 'prim-navitia',
    googleAttributionRequired: googlePlaces.length > 0,
    places,
  }, 200, {
    ...cors,
    'Cache-Control': 'private, max-age=0, no-store',
  });
}

async function fetchGooglePlaceSuggestions(query, sessionToken, apiKey) {
  const response = await fetch('https://places.googleapis.com/v1/places:autocomplete', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': apiKey,
      'X-Goog-FieldMask': [
        'suggestions.placePrediction.placeId',
        'suggestions.placePrediction.text.text',
        'suggestions.placePrediction.structuredFormat.mainText.text',
        'suggestions.placePrediction.structuredFormat.secondaryText.text',
      ].join(','),
    },
    body: JSON.stringify({
      input: query,
      languageCode: 'fr',
      regionCode: 'FR',
      includedRegionCodes: ['fr'],
      locationBias: {
        circle: {
          center: { latitude: 48.8566, longitude: 2.3522 },
          radius: 50000,
        },
      },
      ...(sessionToken ? { sessionToken } : {}),
    }),
  });
  if (!response.ok) {
    throw new ProxyError(`Google Places a répondu ${response.status}.`, 502);
  }
  const payload = await response.json();
  return normalizeGoogleSuggestions(payload, sessionToken);
}

export function normalizeGoogleSuggestions(payload, sessionToken = null) {
  return (Array.isArray(payload?.suggestions) ? payload.suggestions : [])
    .map((suggestion) => suggestion.placePrediction)
    .filter((prediction) => prediction?.placeId && prediction?.text?.text)
    .slice(0, 5)
    .map((prediction) => {
      const name = prediction.structuredFormat?.mainText?.text || prediction.text.text;
      const detail = prediction.structuredFormat?.secondaryText?.text || '';
      return {
        id: `google:${prediction.placeId}`,
        name,
        label: detail ? `${name}, ${detail}` : prediction.text.text,
        type: 'poi',
        provider: 'google',
        ...(sessionToken ? { sessionToken } : {}),
      };
    });
}

function deduplicatePlaceSuggestions(places) {
  const seen = new Set();
  return places.filter((place) => {
    const key = place.label.toLocaleLowerCase('fr').replace(/\s+/g, ' ').trim();
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

async function resolveRequestedPlace(id, name, sessionToken, env) {
  if (!id.startsWith('google:')) return { id, name };
  if (!env.GOOGLE_PLACES_API_KEY) {
    throw new ProxyError('La recherche Google Places n’est pas configurée.', 503);
  }
  const placeId = id.slice('google:'.length);
  if (!placeId) throw new ProxyError('Lieu Google invalide.', 400);
  const params = new URLSearchParams({ languageCode: 'fr', regionCode: 'FR' });
  if (sessionToken) params.set('sessionToken', sessionToken);
  const response = await fetch(
    `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}?${params}`,
    {
      headers: {
        'X-Goog-Api-Key': env.GOOGLE_PLACES_API_KEY,
        'X-Goog-FieldMask': 'id,displayName,formattedAddress,location',
      },
    },
  );
  if (!response.ok) {
    throw new ProxyError(`Google Places a répondu ${response.status}.`, 502);
  }
  const place = await response.json();
  const latitude = Number(place.location?.latitude);
  const longitude = Number(place.location?.longitude);
  if (!validLocation({ lat: latitude, lon: longitude })) {
    throw new ProxyError(`Coordonnées introuvables pour ${name}.`, 404);
  }
  return {
    id: `${longitude};${latitude}`,
    name: place.displayName?.text || place.formattedAddress || name,
  };
}

function normalizePlaceSuggestion(place) {
  const region = place.administrative_region ||
    place.address?.administrative_regions?.find((item) => item.level === 8) ||
    place.stop_area?.administrative_regions?.find((item) => item.level === 8) ||
    place.poi?.administrative_regions?.find((item) => item.level === 8);
  const city = region?.name || '';
  const postcode = region?.zip_code || '';
  const detail = [postcode, city].filter(Boolean).join(' ');
  const name = place.name || place.address?.name || place.stop_area?.name || place.poi?.name || '';
  return {
    id: place.id,
    name,
    label: detail && !name.toLowerCase().includes(city.toLowerCase()) ? `${name}, ${detail}` : name,
    type: place.stop_area ? 'stop_area' : place.poi ? 'poi' : 'address',
    provider: 'prim',
  };
}

function validPlaceId(value) {
  return typeof value === 'string' && value.length <= 200 && /^[A-Za-z0-9_:;.,-]+$/.test(value);
}

function validGoogleSessionToken(value) {
  return typeof value === 'string' && value.length >= 16 && value.length <= 64 &&
    /^[A-Za-z0-9_-]+$/.test(value);
}

async function resolvePlace(base, apiKey, query) {
  const params = new URLSearchParams({ q: query, count: '10' });
  params.append('type[]', 'address');
  params.append('type[]', 'stop_area');
  params.append('type[]', 'poi');
  const payload = await primFetch(`${base}/places?${params}`, apiKey);
  const places = Array.isArray(payload.places) ? payload.places : [];
  const place = places.find((item) => item.id && (item.address || item.stop_area || item.poi));
  if (!place) throw new ProxyError(`Adresse introuvable : ${query}`, 404);
  return { id: place.id, name: place.name || query };
}

export function normalizeJourney(journey) {
  return {
    departureAt: navitiaDateToIso(journey.departure_date_time),
    arrivalAt: navitiaDateToIso(journey.arrival_date_time),
    durationSeconds: Number(journey.duration || 0),
    transfers: Number(journey.nb_transfers || 0),
    recommendedExit: findRecommendedExit(journey.sections),
    sections: (Array.isArray(journey.sections) ? journey.sections : [])
      .filter((section) => !['waiting', 'boarding', 'landing'].includes(section.type))
      .map((section) => ({
        type: section.type || 'transfer',
        mode: section.display_informations?.commercial_mode || section.mode || 'Marche',
        line: section.display_informations?.code || null,
        direction: section.display_informations?.direction || null,
        from: section.from?.name || '',
        to: section.to?.name || '',
        departureAt: section.departure_date_time
          ? navitiaDateToIso(section.departure_date_time)
          : null,
        arrivalAt: section.arrival_date_time
          ? navitiaDateToIso(section.arrival_date_time)
          : null,
        durationSeconds: Number(section.duration || 0),
      })),
  };
}

function findRecommendedExit(sections) {
  const values = Array.isArray(sections) ? sections : [];
  for (const section of [...values].reverse()) {
    const vias = Array.isArray(section.vias) ? section.vias : [];
    for (const via of vias) {
      const access = via.access_point || via;
      if (access.is_exit === false) continue;
      const name = access.signposted_as || access.name;
      const code = access.access_point_code;
      if (name && code && !name.includes(code)) return `${code} — ${name}`;
      if (name || code) return name || code;
    }
  }
  return null;
}

async function stopsResponse(url, request, env, context, cors, lineId) {
  const cacheKey = new Request(`${url.origin}/cache/stops?lineId=${encodeURIComponent(lineId)}`);
  const cache = caches.default;
  const cached = await cache.match(cacheKey);
  if (cached) return withCors(cached, cors);

  const base = env.PRIM_NAVITIA_BASE || 'https://prim.iledefrance-mobilites.fr/marketplace/v2/navitia';
  const payload = await primFetch(
    `${base}/lines/${encodeURIComponent(lineId)}/stop_areas?count=1000`,
    env.PRIM_API_KEY,
  );
  const stops = (Array.isArray(payload.stop_areas) ? payload.stop_areas : [])
    .filter((stop) => validStopId(stop.id))
    .map((stop) => ({ id: stop.id, name: stop.name || 'Arrêt sans nom' }))
    .sort((a, b) => a.name.localeCompare(b.name, 'fr', { numeric: true }));
  const response = json(
    { source: 'prim-navitia', stops },
    200,
    { ...cors, 'Cache-Control': 'public, max-age=86400' },
  );
  context.waitUntil(cache.put(cacheKey, response.clone()));
  return response;
}

async function directionsResponse(url, request, env, context, cors, lineId) {
  const stopId = url.searchParams.get('stopId');
  if (!validStopId(stopId)) return json({ error: 'stopId invalide.' }, 400, cors);
  const cacheKey = new Request(
    `${url.origin}/cache/directions?lineId=${encodeURIComponent(lineId)}&stopId=${encodeURIComponent(stopId)}`,
  );
  const cache = caches.default;
  const cached = await cache.match(cacheKey);
  if (cached) return withCors(cached, cors);

  const base = env.PRIM_NAVITIA_BASE || 'https://prim.iledefrance-mobilites.fr/marketplace/v2/navitia';
  const filter = encodeURIComponent(`line.id=${lineId}`);
  const payload = await primFetch(
    `${base}/stop_areas/${encodeURIComponent(stopId)}/routes?count=100&filter=${filter}`,
    env.PRIM_API_KEY,
  );
  const seen = new Set();
  const directions = (Array.isArray(payload.routes) ? payload.routes : [])
    .filter((route) => validRouteId(route.id))
    .map((route) => ({
      id: route.id,
      label: route.direction?.name || route.name || route.code || 'Direction inconnue',
    }))
    .filter((direction) => {
      if (seen.has(direction.id)) return false;
      seen.add(direction.id);
      return true;
    });
  const response = json(
    { source: 'prim-navitia', directions },
    200,
    { ...cors, 'Cache-Control': 'public, max-age=86400' },
  );
  context.waitUntil(cache.put(cacheKey, response.clone()));
  return response;
}

async function fetchAllLines(base, apiKey, filter) {
  const pageSize = 1000;
  const values = [];
  for (let page = 0; page < 10; page += 1) {
    const payload = await primFetch(
      `${base}/lines?count=${pageSize}&start_page=${page}&filter=${encodeURIComponent(filter)}`,
      apiKey,
    );
    const pageValues = Array.isArray(payload.lines) ? payload.lines : [];
    values.push(...pageValues);
    const total = Number(payload.pagination?.total_result ?? values.length);
    if (values.length >= total || pageValues.length < pageSize) break;
  }
  return values;
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
  if (place) {
    return {
      id: place.stop_area.id,
      name: place.stop_area.name || 'Arrêt à proximité',
      distance: Number(place.distance || 0),
      isNearby: true,
    };
  }

  return referenceStop(base, apiKey, lineId);
}

async function referenceStop(base, apiKey, lineId) {
  const fallbackPayload = await primFetch(
    `${base}/lines/${encodeURIComponent(lineId)}/stop_areas?count=1`,
    apiKey,
  );
  const fallback = Array.isArray(fallbackPayload.stop_areas)
    ? fallbackPayload.stop_areas[0]
    : null;
  if (!fallback?.id) {
    throw new ProxyError(
      'Aucun arrêt exploitable n’est disponible actuellement pour cette ligne.',
      404,
    );
  }
  return {
    id: fallback.id,
    name: fallback.name || 'Arrêt de référence',
    distance: 0,
    isNearby: false,
  };
}

async function trafficAlert(env, lineId) {
  try {
    return await fetchTrafficAlert(env, lineId);
  } catch (_) {
    return null;
  }
}

async function fetchTrafficAlert(env, lineId) {
  const base = env.PRIM_TRAFFIC_BASE || 'https://prim.iledefrance-mobilites.fr/marketplace/v2/navitia/line_reports';
  const filter = encodeURIComponent(`line.id=${lineId}`);
  const payload = await primFetch(
    `${base}?count=20&filter=${filter}`,
    env.PRIM_API_KEY,
  );
  const disruption = (payload.disruptions || []).find((item) => item.status !== 'past');
  if (!disruption) return null;
  const message = (disruption.messages || [])
    .find((item) => item.channel?.content_type === 'text/plain')?.text;
  return {
    title: disruption.severity?.name || 'Information trafic',
    message: message || disruption.cause || 'Une perturbation est signalée sur cette ligne.',
  };
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

class ProxyError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

function proxyErrorResponse(error, cors) {
  const message = error instanceof Error ? error.message : 'Erreur PRIM inconnue.';
  const status = error instanceof ProxyError ? error.status : 502;
  return json({ error: message }, status, cors);
}

function validStopId(value) {
  return typeof value === 'string' && /^stop_area:IDFM:[A-Za-z0-9_-]+$/.test(value);
}

function validRouteId(value) {
  return typeof value === 'string' && /^route:IDFM:[A-Za-z0-9:_-]+$/.test(value);
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
