import assert from 'node:assert/strict';
import test from 'node:test';

import {
  navitiaDateToIso,
  normalizeDepartures,
  normalizeJourney,
  toNavitiaLineId,
} from '../src/index.js';

test('converts a SIRI line reference to a Navitia line id', () => {
  assert.equal(toNavitiaLineId('STIF:Line::C01740:'), 'line:IDFM:C01740');
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
    }],
  });
  assert.match(journey.sections[0].departureAt, /T17:52:00/);
  assert.match(journey.sections[0].arrivalAt, /T18:11:00/);
});
