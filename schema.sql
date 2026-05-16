-- ============================================================
-- Clarke Creek Pool Competition — Supabase Schema v2
-- Run this in: supabase.com → your project → SQL Editor
--
-- IMPORTANT: If upgrading from v1, run the migration section
-- at the bottom AFTER the main schema.
-- ============================================================

-- ── EXTENSIONS ──────────────────────────────────────────────
create extension if not exists "uuid-ossp";

-- ── PLAYERS ─────────────────────────────────────────────────
-- Stores player profiles. Linked to Supabase Auth users.
create table if not exists players (
  id          uuid primary key default uuid_generate_v4(),
  auth_id     uuid unique,                    -- links to auth.users
  name        text not null,
  short       text not null,                  -- 2-3 letter abbreviation
  avatar_url  text,                           -- optional photo URL
  roster      text not null default '1on1off_wed',
  color       text not null default '#c9a84c',
  role        text not null default 'player', -- 'admin' or 'player'
  active      boolean not null default true,
  created_at  timestamptz default now()
);

-- ── SEASONS ─────────────────────────────────────────────────
-- Each competition run is a season. Allows archiving.
create table if not exists seasons (
  id          uuid primary key default uuid_generate_v4(),
  name        text not null default 'Season 1',
  start_date  text,                           -- YYYY-MM-DD
  status      text not null default 'setup',  -- setup | active | complete | archived
  config      jsonb not null default '{
    "ptW": 3,
    "ptD": 1,
    "ptL": 0,
    "prizePerGame": 5,
    "groupCount": 2,
    "qualifyPerGroup": 3,
    "elimination": "single"
  }',
  player_starts jsonb not null default '{}',  -- { playerId: "YYYY-MM-DD" }
  groups        jsonb,                        -- { A: [playerId,...], B: [...] }
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

-- ── FIXTURES ────────────────────────────────────────────────
-- Individual matches in the group stage.
create table if not exists fixtures (
  id          uuid primary key default uuid_generate_v4(),
  season_id   uuid references seasons(id) on delete cascade,
  group_label text not null,                  -- 'A' or 'B'
  p1_id       uuid references players(id),
  p2_id       uuid references players(id),
  scheduled_date text,                        -- YYYY-MM-DD
  result      text,                           -- 'p1' | 'p2' | 'draw' | null
  recorded_by uuid references players(id),
  recorded_at timestamptz,
  created_at  timestamptz default now()
);

-- ── KNOCKOUT MATCHES ────────────────────────────────────────
-- Semi-finals, finals, 3rd place play-offs.
create table if not exists knockout_matches (
  id          uuid primary key default uuid_generate_v4(),
  season_id   uuid references seasons(id) on delete cascade,
  round_id    text not null,                  -- 'sf1' | 'sf2' | 'sf3' | 'final' | 'third'
  label       text not null,
  description text,
  p1_id       uuid,                           -- nullable until seeded
  p2_id       uuid,
  result      text,                           -- 'p1' | 'p2' | null
  recorded_by uuid references players(id),
  recorded_at timestamptz,
  created_at  timestamptz default now()
);

-- ── LEGACY STATE ────────────────────────────────────────────
-- Kept for backward compatibility with v1 single-blob storage.
-- New code uses the tables above; this remains as a fallback.
create table if not exists pool_state (
  key         text primary key,
  "compStart"    text,
  "playerStarts" jsonb,
  "ptW"          integer default 3,
  "ptD"          integer default 1,
  "ptL"          integer default 0,
  groups      jsonb,
  fixtures    jsonb,
  knockout    jsonb,
  updated_at  timestamptz default now()
);

-- ── ROW LEVEL SECURITY ──────────────────────────────────────
-- Public read for all tables (leaderboard is public)
-- Write protected to authenticated users / admins

alter table players          enable row level security;
alter table seasons          enable row level security;
alter table fixtures         enable row level security;
alter table knockout_matches enable row level security;
alter table pool_state       enable row level security;

-- Players: anyone can read
create policy "players_read"  on players for select using (true);
create policy "players_write" on players for all    using (true) with check (true);

-- Seasons: anyone can read
create policy "seasons_read"  on seasons for select using (true);
create policy "seasons_write" on seasons for all    using (true) with check (true);

-- Fixtures: anyone can read
create policy "fixtures_read"  on fixtures for select using (true);
create policy "fixtures_write" on fixtures for all    using (true) with check (true);

-- Knockout: anyone can read
create policy "knockout_read"  on knockout_matches for select using (true);
create policy "knockout_write" on knockout_matches for all    using (true) with check (true);

-- Legacy pool_state
create policy "pool_state_read"   on pool_state for select using (true);
create policy "pool_state_insert" on pool_state for insert with check (true);
create policy "pool_state_update" on pool_state for update using (true);

-- ── REALTIME ────────────────────────────────────────────────
-- Enable realtime on key tables so all devices auto-sync
alter publication supabase_realtime add table fixtures;
alter publication supabase_realtime add table knockout_matches;
alter publication supabase_realtime add table seasons;
alter publication supabase_realtime add table pool_state;

-- ── SEED DEFAULT PLAYERS ────────────────────────────────────
-- Only insert if players table is empty
insert into players (name, short, roster, color) 
select * from (values
  ('Alex Rickard',    'AR', '1on1off_wed', '#c0392b'),
  ('Luke Edwards',    'LE', '1on1off_wed', '#2980b9'),
  ('Luke Boardman',   'LB', '1on1off_wed', '#27ae60'),
  ('Murray Cavanagh', 'MC', '1on1off_wed', '#8e44ad'),
  ('Simon Moroney',   'SM', '1on1off_wed', '#e67e22'),
  ('Christian Clark', 'CC', '1on1off_wed', '#16a085'),
  ('Ivor Ralph',      'IR', '2on2off',     '#d35400'),
  ('John Rowe',       'JR', '2on2off',     '#1abc9c'),
  ('Alex Mitchell',   'AM', '2on1off',     '#f39c12'),
  ('Dan Moor',        'DM', '2on1off',     '#6c5ce7'),
  ('Cameron Ellis',   'CE', '2on2off',     '#e84393'),
  ('Jackson Geddes',  'JG', '2on2off',     '#00b894'),
  ('Kym Gray',        'KG', '2on2off',     '#e17055'),
  ('Bryce Brown',     'BB', '2on2off',     '#0984e3'),
  ('Degen Runge',     'DR', '1on1off_mon', '#b8860b')
) as v(name, short, roster, color)
where not exists (select 1 from players limit 1);
