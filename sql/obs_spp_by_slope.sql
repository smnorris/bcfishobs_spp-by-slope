DROP TABLE IF EXISTS temp.obs_spp_by_slope;

CREATE TABLE temp.obs_spp_by_slope AS

WITH segments AS
(
  SELECT DISTINCT ON (fish_obsrvtn_distinct_id)
      e.fish_obsrvtn_distinct_id,
      s.linear_feature_id,
      s.blue_line_key,
      s.length_metre,
      s.downstream_route_measure,
      e.downstream_route_measure as event_measure,
      (ST_Dump(s.geom)).geom AS geom
    FROM whse_fish.fiss_fish_obsrvtn_events e
    INNER JOIN whse_basemapping.fwa_stream_networks_sp s
    ON e.linear_feature_id = s.linear_feature_id
    AND s.downstream_route_measure < (e.downstream_route_measure + .001)
    ORDER BY e.fish_obsrvtn_distinct_id, s.linear_feature_id, s.downstream_route_measure DESC
),

blue_line_lengths AS
(
    SELECT DISTINCT ON (blue_line_key)
      s.blue_line_key,
      s.downstream_route_measure + s.length_metre AS blue_line_length
    FROM whse_fish.fiss_fish_obsrvtn_events e
    INNER JOIN whse_basemapping.fwa_stream_networks_sp s
    ON e.blue_line_key = s.blue_line_key
    AND s.edge_type != 6010                           -- do not include lines outside of BC
    ORDER BY
      s.blue_line_key,
      s.downstream_route_measure DESC
),


vertices AS
(
  SELECT
    l.fish_obsrvtn_distinct_id,
    l.blue_line_key,
    l.linear_feature_id,
    l.length_metre as segment_length,
    generate_series(1, ST_NPoints(l.geom)) as vertex_id,
    ((ST_LineLocatePoint(l.geom,
                         ST_PointN(l.geom,
                                   generate_series(1,
                                                   ST_NPoints(l.geom)))) * l.length_metre)
      + downstream_route_measure) / tl.blue_line_length  AS pct,
    ST_Z(ST_PointN(l.geom, generate_series(1, ST_NPoints(l.geom)))) AS elevation,
    l.downstream_route_measure,
    tl.blue_line_length,
    l.event_measure
  FROM segments l
  INNER JOIN blue_line_lengths tl ON l.blue_line_key = tl.blue_line_key
  ORDER BY l.blue_line_key, l.downstream_route_measure, pct
),


-- create edges between the vertices, as from and to percentages and elevations
prelim_edges AS
(
  SELECT
     fish_obsrvtn_distinct_id,
     linear_feature_id,
     segment_length,
     downstream_route_measure,
     vertex_id,
     pct AS from_pct,
     lead(pct) OVER(ORDER BY fish_obsrvtn_distinct_id, blue_line_key, pct) AS to_pct,
     elevation AS from_elevation,
     lead(elevation) OVER(ORDER BY fish_obsrvtn_distinct_id, blue_line_key, pct) AS to_elevation,
     blue_line_length,
     event_measure
  FROM vertices
  ORDER BY
    fish_obsrvtn_distinct_id,
    linear_feature_id,
    pct
),

edges as
(
    SELECT DISTINCT ON (fish_obsrvtn_distinct_id)
      fish_obsrvtn_distinct_id,
      linear_feature_id,
      downstream_route_measure,
      segment_length,
      event_measure,
      vertex_id as edge_id,
      from_pct,
      to_pct,
      blue_line_length,
      (blue_line_length * from_pct) as edge_downstream_route_measure,
      (blue_line_length * to_pct) as edge_upstream_route_measure,
      blue_line_length * (to_pct - from_pct) AS edge_length_metres,
      round(from_elevation::numeric, 2) AS from_elevation,
      round(to_elevation::numeric, 2) as to_elevation,
      ROUND(((((to_elevation - from_elevation) / (blue_line_length * (to_pct - from_pct))) * 100))::numeric, 2) AS slope
    FROM prelim_edges
       -- don't return anything that :
       -- - starts at 100%
    WHERE round(from_pct::numeric, 5) <> 1
       -- - starts at the end of virtual segment (created by the lead() function)
    AND round(from_pct::numeric, 5) != ROUND(((downstream_route_measure + segment_length) / blue_line_length)::numeric, 5)
       -- - has no length (there shouldn't be any but make sure, we don't want to divide by zero)
    AND to_pct != from_pct
       -- - has no elevation (there shouldn't be any of these)
    AND to_elevation IS NOT NULL
    ORDER BY fish_obsrvtn_distinct_id, linear_feature_id, from_pct
),


slopes as
(
  SELECT
      e.fish_obsrvtn_distinct_id,
      e.linear_feature_id,
      s.edge_type,
      ec.edge_description,
      e.downstream_route_measure,
      s.waterbody_key,
      wb.waterbody_type,
      e.from_elevation as vertex_from_elevation,
      e.to_elevation as vertex_to_elevation,
      round(e.edge_length_metres::numeric, 2) as vertex_length,
      e.slope as vertex_slope,
      ST_Z(ST_Startpoint((ST_Dump(s.geom)).geom)) as segment_from_elevation,
      ST_Z(ST_Endpoint((ST_Dump(s.geom)).geom)) as segment_to_elevation,
      round(s.length_metre::numeric, 2) as segment_length,
      ROUND((((ST_Z(ST_Endpoint((ST_Dump(s.geom)).geom)) -
         ST_Z(ST_Startpoint((ST_Dump(s.geom)).geom))) / length_metre) * 100)::numeric, 2) as segment_slope
  FROM edges e
  INNER JOIN whse_basemapping.fwa_stream_networks_sp s
  ON e.linear_feature_id = s.linear_feature_id
  INNER JOIN whse_basemapping.fwa_edge_type_codes ec
  ON s.edge_type = ec.edge_type
  LEFT OUTER JOIN whse_basemapping.waterbodies wb
  ON s.waterbody_key = wb.waterbody_key
),

slopes_by_spp AS
(
    SELECT DISTINCT
      s.*,
      unnest(d.species_codes) as species_code
    FROM slopes s
    INNER JOIN whse_fish.fiss_fish_obsrvtn_distinct d
    ON s.fish_obsrvtn_distinct_id = d.fish_obsrvtn_distinct_id
)


SELECT
  obs.*,
  sp.name AS species_name
FROM slopes_by_spp obs
INNER JOIN whse_fish.species_cd sp ON obs.species_code = sp.code;
