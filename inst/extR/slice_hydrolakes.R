library(sf)
source("R/AAA.R")
source("inst/extR/general_functions.R")

hydrolakes_path = "E:/hydrolakes/HydroLAKES_polys_v10_shp"
#hydrolakes_path = "B:/big_data/HydroLAKES_polys_v10_shp"

#id_table_output_path = "E:/hydrolinks_tables"
#id_table_output_path = "B:/big_data/hydrolinks_tables"

hydrolakes = st_read(file.path(hydrolakes_path, "HydroLAKES_polys_v10.shp"))
hydrolakes = st_transform(hydrolakes, nhd_projected_proj)
centroids = st_centroid(hydrolakes)
hydrolakes$centroid.x = st_coordinates(centroids)[,"X"]
hydrolakes$centroid.x = st_coordinates(centroids)[,"Y"]
hydrolakes = hydrolakes[order(hydrolakes$centroid.x), ]

#setup the slices, evenly distributed across the whole dataset
nslices = 50
indx = floor(seq(1, nrow(hydrolakes), length.out = (nslices+1)))

bboxes = list()
for(i in 1:(length(indx)-1)){
  slice = hydrolakes[indx[i]:indx[i+1], ]
  dir.create(file.path(hydrolakes_path, paste0("hydrolakes_", i)))
  #slice = st_transform(slice, nhd_projected_proj)
  #centroids = st_centroid(slice)
  #slice$centroid.x = st_coordinates(centroids)[,"X"]
  #slice$centroid.y = st_coordinates(centroids)[,"Y"]
  names(slice) = tolower(names(slice))
  st_write(slice, dsn = file.path(hydrolakes_path, paste0("hydrolakes_", i)), layer = "HydroLAKES_polys_v10_projected",
           driver = "ESRI Shapefile")
  bboxes[[i]] = st_sf(file = paste0("hydrolakes_", i, ".zip"), geometry=st_as_sfc(st_bbox(slice), crs=nhd_projected_proj), stringsAsFactors = FALSE)
}

bbdf = do.call(rbind, bboxes)
save(bbdf, file='inst/extdata/hydrolakes_bb_cache.Rdata')

working_directory = getwd()
dir.create(file.path(output_folder, "hydrolakes"))
output_zip = file.path(output_folder, "hydrolakes", paste0("hydrolakes_", 1:nslices, ".zip"))
for(i in 1:nslices){
  tozip = Sys.glob(file.path(hydrolakes_path, paste0("hydrolakes_", i), '*'))
  zip(output_zip[i], files=tozip, flags='-j')
}

#setwd(hydrolakes_path)
build_id_table(bbdf, "HydroLAKES_polys_v10_projected.shp", file.path(id_table_output_path, "hydrolakes_waterbody_ids.sqlite3"), 
               c("Hylak_id", "Lake_name"), file.path(hydrolakes_path, paste0("hydrolakes_", 1:nslices)))

#setwd(working_directory)
processed_shapes = gen_upload_file(output_zip, file.path(remote_path, "hydrolakes"))
write.csv(processed_shapes, "inst/extdata/hydrolakes.csv", row.names=FALSE, quote=FALSE)
