# bcfishobs_spp-by-slope

An attempt to determine the maximum slope passable by various fish species.

### Requirements
- [`fwakit`](https://github.com/smnorris/fwakit)
- [`bcfishobs`](https://github.com/smnorris/bcfishobs)

These repositories outline their individual requirements.

### Run analysis

With the observation events created by `bcfishobs`, run the slope analysis with:

```
psql -f sql/obs_spp_by_slope.sql
```

### Dump observation-slope data to file

```
psql2csv "SELECT * FROM temp.obs_spp_by_slope" > obs_spp_by_slope.csv
zip -r obs_spp_by_slope.zip obs_spp_by_slope.csv
```