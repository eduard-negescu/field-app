import { and, eq, inArray, lt, notInArray } from 'drizzle-orm';
import { useLiveQuery } from 'drizzle-orm/expo-sqlite';
import * as Crypto from 'expo-crypto';
import { create } from 'zustand';
import type { Building, Entrance, EntranceSurvey } from './contract/contract';
import { ME } from './contract/fixtures';
import { db } from './db/db';
import { buildings, entrances } from './db/schema';

// ---------------------------------------------------------------------------
// The data lives in SQLite. Screens read it with live queries: when a write
// changes a table, every screen reading that table re-renders by itself.
// ---------------------------------------------------------------------------

export function useEntrances(): Entrance[] {
  return useLiveQuery(db.select().from(entrances)).data;
}

/** undefined while SQLite answers the first time, null when there is no such row. */
export function useEntrance(id: string): Entrance | null | undefined {
  const { data, updatedAt } = useLiveQuery(
    db.select().from(entrances).where(eq(entrances.id, id)),
    [id],
  );
  return updatedAt ? (data[0] ?? null) : undefined;
}

export function useBuilding(id: string): Building | undefined {
  return useLiveQuery(db.select().from(buildings).where(eq(buildings.id, id)), [id]).data[0];
}

/** The survey goes to SQLite: it survives a restart, and waits for week 4's push. */
export async function submitSurvey(id: string, survey: EntranceSurvey) {
  const now = new Date().toISOString();
  await db
    .update(entrances)
    .set({
      ...survey,
      surveyStatus: 'submitted',
      surveyedBy: ME,
      surveyedAt: now,
      updatedAt: now,
      syncState: 'pending', // the office has not seen this version yet
      lastError: null,
    })
    .where(eq(entrances.id, id));
}

/**
 * A building the office missed: the worker stands at its door and makes both
 * rows on the phone, with ids born here (UUID v4). The office will learn of it
 * at the first sync (week 4); until then it is 'pending', like any new row.
 */
export async function addMissedEntrance(at: { lat: number; lng: number }): Promise<string> {
  const now = new Date().toISOString();
  const buildingId = Crypto.randomUUID();
  const entranceId = Crypto.randomUUID();
  await db.insert(buildings).values({
    id: buildingId,
    createdAt: now,
    updatedAt: now,
    label: 'New building',
    comment: 'Added in the field: not on the office map.',
    syncState: 'pending',
  });
  await db.insert(entrances).values({
    id: entranceId,
    createdAt: now,
    updatedAt: now,
    buildingId,
    lat: at.lat,
    lng: at.lng,
    street: '?', // the survey asks for the real address
    number: '?',
    entranceName: 'Sc. 1',
    coordsConfirmed: true, // the pin is where the worker stands: at the door
    correctedLat: null,
    correctedLng: null,
    addressConfirmed: false,
    stories: null,
    flats: null,
    elevators: null,
    yearBuilt: null,
    groundFloorCommercial: null,
    comment: null,
    surveyStatus: 'in_progress',
    surveyedBy: null,
    surveyedAt: null,
    syncState: 'pending',
  });
  return entranceId;
}

/**
 * The pull: the cloud's list of my pins becomes the entrances table. A pin
 * updates its row only when it is newer (updatedAt) than the row, and never
 * over an unsent survey (syncState pending or failed): the survey the worker
 * just sent is newer than the office's pin, so it stays on screen. A synced
 * row that is no longer in the list was taken away: deleted.
 */
export async function savePins(pins: Entrance[]) {
  for (const pin of pins) {
    const row = { ...pin, syncState: 'synced' as const, lastError: null };
    await db
      .insert(entrances)
      .values(row)
      .onConflictDoUpdate({
        target: entrances.id,
        set: row,
        setWhere: and(eq(entrances.syncState, 'synced'), lt(entrances.updatedAt, pin.updatedAt)),
      });
  }
  await db.delete(entrances).where(
    and(
      eq(entrances.syncState, 'synced'),
      notInArray(
        entrances.id,
        pins.map((p) => p.id),
      ),
    ),
  );
}

/**
 * The outbox: submitted surveys the cloud has not confirmed yet. A missed
 * building (week 3) waits: its building is not in the cloud before week 5.
 */
export async function outbox() {
  const rows = await db
    .select({ entrance: entrances })
    .from(entrances)
    .innerJoin(buildings, eq(entrances.buildingId, buildings.id))
    .where(
      and(
        eq(entrances.surveyStatus, 'submitted'),
        inArray(entrances.syncState, ['pending', 'failed']),
        eq(buildings.syncState, 'synced'),
      ),
    );
  return rows.map((r) => r.entrance);
}

/** After a push: synced, unless the worker changed the survey meanwhile. */
export async function markSent(id: string, updatedAt: string, error: string | null) {
  await db
    .update(entrances)
    .set(error ? { syncState: 'failed', lastError: error } : { syncState: 'synced', lastError: null })
    .where(and(eq(entrances.id, id), eq(entrances.updatedAt, updatedAt)));
}

/** The banner's count: what still waits to be sent, and the last refusal. */
export function useOutbox() {
  const { data } = useLiveQuery(
    db
      .select({ syncState: entrances.syncState, lastError: entrances.lastError })
      .from(entrances)
      .where(inArray(entrances.syncState, ['pending', 'failed'])),
  );
  return {
    pending: data.filter((r) => r.syncState === 'pending').length,
    failed: data.filter((r) => r.syncState === 'failed').length,
    lastError: data.find((r) => r.lastError)?.lastError ?? null,
  };
}

// ---------------------------------------------------------------------------
// Everything that is not data — where the phone is, which way it faces, the
// network — is client state, in one Zustand store. Steps 7 and 12 fill it.
// ---------------------------------------------------------------------------

export type Fix = { lat: number; lng: number; accuracy: number | null; at: string };

type FieldState = {
  fix: Fix | null;
  heading: number | null;
  setFix: (fix: Fix | null) => void;
  setHeading: (heading: number | null) => void;
};

export const useField = create<FieldState>()((set) => ({
  fix: null,
  heading: null,
  setFix: (fix) => set({ fix }),
  setHeading: (heading) => set({ heading }),
}));
