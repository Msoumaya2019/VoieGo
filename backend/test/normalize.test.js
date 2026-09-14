import assert from 'node:assert/strict';
import test from 'node:test';

import {
  navitiaDateToIso,
  normalizeDepartures,
  normalizeJourney,
  normalizeGoogleSuggestions,
  toNavitiaLineId,
} from '../src/index.js';

test('converts a SIRI line reference to a Navitia line id', () => {
  assert.equal(toNavitiaLineId('STIF:Line::C01740:'), 'line:IDFM:C01740');
});

test('normalizes Google business suggestions without exposing the API key', () => {
  const result = normalizeGoogleSuggestions({
    suggestions: [{
      placePrediction: {
        placeId: 'ChIJ-test',
        text: { text: 'Centre dentaire, Louvres' },
        structuredFormat: {
          mainText: { text: 'Centre dentaire' },
          secondaryText: { text: 'Louvres, France' },
        },
      },
    }],
  }, 'session_token_123456');
  assert.deepEqual(result[0], {
    id: 'google:ChIJ-test',
    name: 'Centre dentaire',
    label: 'Centre dentaire, Louvres, France',
    type: 'poi',
    provider: 'google',
    sessionToken: 'session_token_123456',
  });
});

test('normalizes a realtime Navitia departure', () => {
  const result = normalizeDepartures(
    {
      departures: [{
        display_informations: { direction: 'Versailles Rive Droite', headsign: 'VASA' },
        stop_date_time: { departure_date_time: '20260912T143000', data_freshness: 'realtime' },
        stop_point: { name: 'La Défense' },
      }],
    },
    { name: 'La Défense', distance: 320 },
  );
  assert.equal(result[0].destination, 'Versailles Rive Droite');
  assert.equal(result[0].walkingMinutes, 4);
  assert.equal(result[0].confidence, 'confiance élevée');
});

test('converts Navitia local datetime to an ISO value', () => {
  assert.match(navitiaDateToIso('20260912T143000'), /^2026-09-12T14:30:00\+02:00$/);
});

test('keeps exact departure and arrival times for every journey section', () => {
  const journey = normalizeJourney({
    departure_date_time: '20260912T175000',
    arrival_date_time: '20260912T183000',
    duration: 2400,
    nb_transfers: 0,
    sections: [{
      type: 'public_transport',
      departure_date_time: '20260912T175200',
      arrival_date_time: '20260912T181100',
      display_informations: { commercial_mode: 'RER', code: 'D' },
      from: { name: 'Gare de départ' },
      to: { name: 'Gare d’arrivée' },
      duration: 1140,
      vias: [{
        access_point_code: '3',
        signposted_as: 'Rue de Rivoli',
        is_exit: true,
      }],
    }],
  });
  assert.match(journey.sections[0].departureAt, /T17:52:00/);
  assert.match(journey.sections[0].arrivalAt, /T18:11:00/);
  assert.equal(journey.recommendedExit, '3 — Rue de Rivoli');
});
