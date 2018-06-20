
WITH slopes AS
(
    SELECT
      e.fiss_fish_obsrvtn_distinct_id,
      e.blue_line_key,
      s.edge_type,
      ec.edge_description,
      e.downstream_route_measure,
      e.waterbody_key,
      wb.waterbody_type,
      round(fwa_streamslope(e.blue_line_key, e.downstream_route_measure)::numeric, 4) as vertex_slope,
      ST_Z(ST_Startpoint((ST_Dump(s.geom)).geom)) as segment_from_elevation,
      ST_Z(ST_Endpoint((ST_Dump(s.geom)).geom)) as segment_to_elevation,
      s.length_metre as segment_length,
      round(((ST_Z(ST_Endpoint((ST_Dump(s.geom)).geom)) -
         ST_Z(ST_Startpoint((ST_Dump(s.geom)).geom))) / length_metre)::numeric, 4) as sebment_slope
    FROM whse_fish.fiss_fish_obsrvtn_events e
    INNER JOIN whse_basemapping.fwa_stream_networks_sp s
    ON e.linear_feature_id = s.linear_feature_id
    INNER JOIN whse_basemapping.fwa_edge_type_codes ec
    ON s.edge_type = ec.edge_type
    LEFT OUTER JOIN whse_basemapping.waterbodies wb
    ON e.waterbody_key = wb.waterbody_key
),


slopes_by_spp AS
(
    SELECT
      s.*,
      unnest(d.species_codes) as species_code
    FROM slopes s
    INNER JOIN whse_fish.fiss_fish_obsrvtn_distinct d
    ON s.fiss_fish_obsrvtn_distinct_id = d.fiss_fish_obsrvtn_distinct_id
)

SELECT
  obs.*,
  sp.name as species_name
FROM slopes_by_spp obs
INNER JOIN whse_fish.species_cd sp ON obs.species_code = sp.code
