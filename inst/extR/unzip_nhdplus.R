library(sf)
library(parallel)
library(dplyr)
source("R/AAA.R")
source("inst/extR/general_functions.R")

nhd_path = "E:/NHDPlusV21/Data"

regions = c("NE_01", "MA_02", "SA_03N", "SA_03S", "SA_03W", "GL_04", "MS_05", "MS_06", "MS_07", "MS_08",
            "MS_10L", "MS_10U", "MS_11", "SR_09", "TX_12", "RG_13", "CO_14", "CO_15", "GB_16", "PN_17", "CA_18",
            "HI_20", "CI_21", "PI_22AS", "PI_22GU", "PI_22MP")
dir_names = paste0("NHDPlus", substr(regions, 1, 2))

dest = file.path(nhd_path, "unzip")
#id_table_output_path = "D:/hydrolinks_tables"
#this is inherited from the calling script

zipfiles = c()

# traverse nhdplus directory structure and extract nhd snapshot data paths
j = 2
for(i in 1:length(dir_names)){
  zipfile = Sys.glob(file.path(nhd_path, dir_names[i], paste0("NHDPlusV21_", regions[i], "_NHDSnapshot_*")))
  if(length(zipfile) == 0){
    subdirs = list.dirs(file.path(nhd_path, dir_names[i]))
    zipfile = Sys.glob(file.path(subdirs[j], paste0("NHDPlusV21_", regions[i], "_NHDSnapshot_*")))
    j = j + 1
    if(j > length(subdirs)){
      j = 2
    }
  }
  else{
    j = 2
  }
  zipfiles[i] = zipfile
}

for(i in 1:length(zipfiles)){
  system("cmd.exe", input = paste0('"C:/Program Files/7-Zip/7z.exe" e ', zipfiles[i], " -o\"", file.path(dest, regions[i])))
}

waterbody_shapes = file.path(dest, regions, "NHDWaterbody.shp")
flowline_shapes = file.path(dest, regions, "NHDFlowline.shp")

lake_args = data.frame(shape_path = waterbody_shapes, layer = rep("NHDWaterbody_projected", length(waterbody_shapes)),
                       output_name = rep(NA, length(waterbody_shapes)), stringsAsFactors = FALSE)
for(i in 1:length(waterbody_shapes)){
  lake_args[i,3] = paste0(basename(dirname(waterbody_shapes[i])), ".zip")
}

stream_args = data.frame(shape_path = flowline_shapes, layer = rep("NHDFlowline_projected", length(flowline_shapes)),
                       output_name = rep(NA, length(flowline_shapes)), stringsAsFactors = FALSE)
for(i in 1:length(waterbody_shapes)){
  stream_args[i,3] = paste0(basename(dirname(flowline_shapes[i])), ".zip")
}

# project and generate bounding boxes 
c1 = makePSOCKcluster(rep('localhost', 8))
parallel::clusterEvalQ(c1, {library(sf)})
bboxes_waterbody = parApply(c1, lake_args, project_and_get_bb, MARGIN = 1)
bboxes_flowline = parApply(c1, stream_args, project_and_get_bb, MARGIN = 1)

bbdf = do.call(rbind, bboxes_waterbody)
save(bbdf, file = "inst/extdata/nhdplus_waterbody_bb_cache.rdata")

bbdf = do.call(rbind, bboxes_flowline)
save(bbdf, file = "inst/extdata/nhdplus_flowline_bb_cache.rdata")
stopCluster(c1)

# zip projected shapes

#dir.create(file.path(nhd_path, "zip"))
output_zip = file.path(output_folder, 'nhdplusv2', paste0(basename(regions), ".zip"))
dir.create(dirname(output_zip[1]))
for(i in 1:length(regions)){
  #setwd(file.path(dest, regions[i]))
  zip(output_zip[i], Sys.glob(file.path(dest, regions[i], "*_projected.*")), flags='-j')
}

#build id lookup tables

build_id_table(bbdf, layer="NHDFlowline_projected.shp", file_name=file.path(id_table_output_path, "nhdplusv2_flowline_ids.sqlite3"), 
               index_columns=c("COMID", "GNIS_ID", "GNIS_NAME", "REACHCODE"), shape_locations=file.path(dest, regions))

bbdf = do.call(rbind, bboxes_waterbody)
build_id_table(bbdf, layer="NHDWaterbody_projected.shp", file_name=file.path(id_table_output_path, "nhdplusv2_waterbody_ids.sqlite3"), 
               index_columns=c("COMID", "GNIS_ID", "GNIS_NAME", "REACHCODE"), shape_locations=file.path(dest, regions))

for(i in 1:length(zipfiles)){
  system("cmd.exe", input = paste0("\"C:\\Program Files\\7-Zip\\7z.exe\" e ", Sys.glob(file.path(dirname(zipfiles[i]), paste0("NHDPlusV21_", regions[i],"_NHDPlusAttributes_*", ".7z"))), " -o\"", file.path(dest, regions[i])))
}

#build flowtable
raw_tables = file.path(dest, regions, "PlusFlow.dbf")
shape_directories = file.path(dest, regions)
format_flowtable(raw_tables, shape_directories, "WBAREACOMI", "FROMCOMID", "TOCOMID", "COMID", file.path(output_folder, "flowtable_nhdplusv2"))

processed_shapes = gen_upload_file(output_zip, file.path(remote_path, "nhdplusv2"))
write.csv(processed_shapes, "inst/extdata/nhdplusv2.csv", quote=FALSE, row.names=FALSE)
