CREATE TABLE IF NOT EXISTS public.solaredge
(
    time         timestamp WITH TIME ZONE NOT NULL,
    grid         double precision,
    load         double precision,
    pv           double precision,
    import       double precision,
    export       double precision,
    importexport double precision
);

ALTER TABLE public.solaredge
    OWNER TO postgres;

CREATE INDEX IF NOT EXISTS solaredge_time_idx ON public.solaredge (time DESC);

CREATE TABLE IF NOT EXISTS public.portal_statistics
(
    start                            timestamp WITH TIME ZONE
        CONSTRAINT portal_statistics_pk UNIQUE,
    "end"                            timestamp WITH TIME ZONE,
    production                       double precision,
    consumption                      double precision,
    self_consumption_for_production  double precision,
    self_consumption_for_consumption double precision,
    import                           double precision,
    export                           double precision,
    modified                         timestamp DEFAULT now()
);

ALTER TABLE public.portal_statistics
    OWNER TO postgres;

CREATE TABLE IF NOT EXISTS public.portal_statistics_history
(
    time                             timestamp WITH TIME ZONE
        CONSTRAINT portal_statistics_history_pk UNIQUE,
    start                            timestamp WITH TIME ZONE,
    "end"                            timestamp WITH TIME ZONE,
    production                       double precision,
    consumption                      double precision,
    self_consumption_for_production  double precision,
    self_consumption_for_consumption double precision,
    import                           double precision,
    export                           double precision,
    modified                         timestamp DEFAULT now()
);

ALTER TABLE public.portal_statistics_history
    OWNER TO postgres;

CREATE OR REPLACE VIEW public.solaredge_energy
            (time, grid_total, load_total, pv_total, import_total, export_total, importexport_total) AS
SELECT t."time",
       coalesce(sum(t.grid_dx) OVER (ORDER BY t."time"), 0::double precision)::numeric(18, 3)         AS grid_total,
       coalesce(sum(t.load_dx) OVER (ORDER BY t."time"), 0::double precision)::numeric(18, 3)         AS load_total,
       coalesce(sum(t.pv_dx) OVER (ORDER BY t."time"), 0::double precision)::numeric(18, 3)           AS pv_total,
       coalesce(sum(t.import_dx) OVER (ORDER BY t."time"), 0::double precision)::numeric(18, 3)       AS import_total,
       coalesce(sum(t.export_dx) OVER (ORDER BY t."time"), 0::double precision)::numeric(18, 3)       AS export_total,
       coalesce(sum(t.importexport_dx) OVER (ORDER BY t."time"),
                0::double precision)::numeric(18, 3)                                                  AS importexport_total
FROM (SELECT solaredge."time",
             (solaredge.grid + lag(solaredge.grid) OVER w) / 2::double precision *
             (date_part('epoch'::text, solaredge."time") - lag(date_part('epoch'::text, solaredge."time")) OVER w) /
             3600::double precision AS grid_dx,
             (solaredge.load + lag(solaredge.load) OVER w) / 2::double precision *
             (date_part('epoch'::text, solaredge."time") - lag(date_part('epoch'::text, solaredge."time")) OVER w) /
             3600::double precision AS load_dx,
             (solaredge.pv + lag(solaredge.pv) OVER w) / 2::double precision *
             (date_part('epoch'::text, solaredge."time") - lag(date_part('epoch'::text, solaredge."time")) OVER w) /
             3600::double precision AS pv_dx,
             (solaredge.import + lag(solaredge.import) OVER w) / 2::double precision *
             (date_part('epoch'::text, solaredge."time") - lag(date_part('epoch'::text, solaredge."time")) OVER w) /
             3600::double precision AS import_dx,
             (solaredge.export + lag(solaredge.export) OVER w) / 2::double precision *
             (date_part('epoch'::text, solaredge."time") - lag(date_part('epoch'::text, solaredge."time")) OVER w) /
             3600::double precision AS export_dx,
             (solaredge.importexport + lag(solaredge.importexport) OVER w) / 2::double precision *
             (date_part('epoch'::text, solaredge."time") - lag(date_part('epoch'::text, solaredge."time")) OVER w) /
             3600::double precision AS importexport_dx
      FROM solaredge
      WINDOW w AS (ORDER BY solaredge."time")) t;

ALTER TABLE public.solaredge_energy
    OWNER TO postgres;

CREATE OR REPLACE VIEW public.peak_production_times(day, time, peak_production) AS
SELECT peak.day, peak."time"::time WITHOUT TIME ZONE AS "time", peak.peak_production
FROM (SELECT DISTINCT ON (peak_production_values.day) peak_production_values.day,
                                                      timezone('europe/berlin'::text, solaredge."time") AS "time",
                                                      peak_production_values.peak_production
      FROM (SELECT timezone('europe/berlin'::text, date_trunc('day'::text, solaredge_1."time")) AS day,
                   max(solaredge_1.pv)                                                          AS peak_production
            FROM solaredge solaredge_1
            GROUP BY (timezone('europe/berlin'::text,
                               date_trunc('day'::text, solaredge_1."time")))) peak_production_values
               JOIN solaredge solaredge ON peak_production_values.day = timezone('europe/berlin'::text,
                                                                                 date_trunc('day'::text, solaredge."time")) AND
                                           solaredge.pv = peak_production_values.peak_production
      ORDER BY peak_production_values.day, (timezone('europe/berlin'::text, solaredge."time"))) peak;

ALTER TABLE public.peak_production_times
    OWNER TO postgres;

CREATE OR REPLACE VIEW public.kosten
            (tag, bezug_preis_netto, bezug_preis_brutto, einspeisung_preis_netto, einspeisung_preis_brutto, verbrauch,
             verbrauch_kosten_netto, verbrauch_kosten_brutto, eigenverbrauch, eigenverbrauch_kosten_netto,
             eigenverbrauch_kosten_brutto, import, import_kosten_netto, import_kosten_brutto, export,
             export_kosten_netto, export_kosten_brutto, "Bilanz")
AS
SELECT portal_statistics.start                                                                                   AS tag,
       p.bezug_netto::money                                                                                      AS bezug_preis_netto,
       p.bezug_brutto::money                                                                                     AS bezug_preis_brutto,
       p.einspeisung_netto::money                                                                                AS einspeisung_preis_netto,
       p.einspeisung_brutto::money                                                                               AS einspeisung_preis_brutto,
       portal_statistics.consumption / 1000::double precision                                                    AS verbrauch,
       portal_statistics.consumption / 1000::double precision *
       p.bezug_netto::money                                                                                      AS verbrauch_kosten_netto,
       portal_statistics.consumption / 1000::double precision *
       p.bezug_brutto::money                                                                                     AS verbrauch_kosten_brutto,
       portal_statistics.self_consumption_for_consumption /
       1000::double precision                                                                                    AS eigenverbrauch,
       portal_statistics.self_consumption_for_consumption / 1000::double precision *
       p.einspeisung_netto::money                                                                                AS eigenverbrauch_kosten_netto,
       portal_statistics.self_consumption_for_consumption / 1000::double precision *
       p.einspeisung_brutto::money                                                                               AS eigenverbrauch_kosten_brutto,
       portal_statistics.import / 1000::double precision                                                         AS import,
       portal_statistics.import / 1000::double precision *
       p.bezug_netto::money                                                                                      AS import_kosten_netto,
       portal_statistics.import / 1000::double precision *
       p.bezug_brutto::money                                                                                     AS import_kosten_brutto,
       portal_statistics.export / 1000::double precision                                                         AS export,
       portal_statistics.export / 1000::double precision *
       p.einspeisung_netto::money                                                                                AS export_kosten_netto,
       portal_statistics.export / 1000::double precision *
       p.einspeisung_brutto::money                                                                               AS export_kosten_brutto,
       portal_statistics.self_consumption_for_consumption / 1000::double precision * p.bezug_netto::money +
       portal_statistics.export / 1000::double precision *
       p.einspeisung_netto::money                                                                                AS "Bilanz"
FROM portal_statistics
         LEFT JOIN preise p ON p.gueltig_ab = ((SELECT pi.gueltig_ab
                                                FROM preise pi
                                                WHERE pi.gueltig_ab <= portal_statistics.start
                                                ORDER BY pi.gueltig_ab DESC
                                                LIMIT 1));

ALTER TABLE public.kosten
    OWNER TO postgres;

