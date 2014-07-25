FUNCTION fhd_setup,file_path_vis,status_str,export_images=export_images,cleanup=cleanup,recalculate_all=recalculate_all,$
    beam_recalculate=beam_recalculate,mapfn_recalculate=mapfn_recalculate,grid_recalculate=grid_recalculate,$
    n_pol=n_pol,flag_visibilities=flag_visibilities,deconvolve=deconvolve,transfer_mapfn=transfer_mapfn,$
    healpix_recalculate=healpix_recalculate,snapshot_recalculate=snapshot_recalculate,$
    file_path_fhd=file_path_fhd,force_data=force_data,force_no_data=force_no_data,$
    calibrate_visibilities=calibrate_visibilities,transfer_calibration=transfer_calibration,$
    weights_grid=weights_grid,save_visibilities=save_visibilities,$
    snapshot_healpix_export=snapshot_healpix_export,log_store=log_store
    
IF N_Elements(recalculate_all) EQ 0 THEN recalculate_all=1
IF N_Elements(calibrate_visibilities) EQ 0 THEN calibrate_visibilities=0
IF N_Elements(beam_recalculate) EQ 0 THEN beam_recalculate=recalculate_all
IF N_Elements(grid_recalculate) EQ 0 THEN grid_recalculate=recalculate_all
IF N_Elements(healpix_recalculate) EQ 0 THEN healpix_recalculate=0
IF N_Elements(flag_visibilities) EQ 0 THEN flag_visibilities=0
IF N_Elements(transfer_mapfn) EQ 0 THEN transfer_mapfn=0
IF N_Elements(save_visibilities) EQ 0 THEN save_visibilities=1
IF N_Elements(snapshot_recalculate) EQ 0 THEN snapshot_recalculate=recalculate_all

fhd_save_io,0,status_str,file_path_fhd=file_path_fhd,var='status_str'

IF Keyword_Set(n_pol) THEN n_pol1=n_pol ELSE BEGIN
    IF status_str.obs GT 0 THEN BEGIN
        fhd_save_io,status_str,obs_temp,file_path_fhd=file_path_fhd,var_name='obs',/restore
        n_pol1=obs_temp.n_pol
    ENDIF ELSE n_pol1=4 ;doesn't really matter what this is set to if the obs structure doesn't even exist
ENDELSE

data_flag=status_str.obs*status_str.params*status_str.flag_arr*status_str.psf*status_str.antenna*status_str.jones
;IF Keyword_set(calibrate_visibilities) THEN data_flag=1
IF Keyword_Set(save_visibilities) THEN data_flag*=Min(status_str.vis[0:n_pol1-1])
IF N_Elements(deconvolve) EQ 0 THEN IF status_str.fhd LE 0 THEN deconvolve=1
IF Keyword_Set(deconvolve) THEN BEGIN
    IF N_Elements(mapfn_recalculate) EQ 0 THEN mapfn_recalculate=recalculate_all
    IF size(transfer_mapfn,/type) EQ 7 THEN BEGIN
        fhd_save_io,status_mapfn,file_path_fhd=file_path_fhd,transfer=transfer_mapfn
        IF Min(status_mapfn.map_fn[0:n_pol1-1]) LE 0 THEN mapfn_recalculate=1 ELSE mapfn_recalculate=0
    ENDIF ELSE IF Min(status_str.map_fn[0:n_pol1-1]) LE 0 THEN mapfn_recalculate=1
    IF Min(status_str.grid_uv[0:n_pol1-1]) LE 0 THEN grid_recalculate=1
ENDIF ELSE IF N_Elements(mapfn_recalculate) EQ 0 THEN mapfn_recalculate=0
IF mapfn_recalculate GT 0 THEN grid_recalculate=1
IF grid_recalculate GT 0 THEN data_flag=0

IF Keyword_Set(beam_recalculate) THEN BEGIN
    status_str.psf=0
    status_str.antenna=0
    status_str.jones=0
ENDIF
IF Keyword_Set(healpix_recalculate) THEN status_str.hpx_cnv=0
IF Keyword_Set(mapfn_recalculate) THEN grid_recalculate=1
IF Keyword_Set(grid_recalculate) THEN BEGIN
    status_str.map_fn[*]=0
    status_str.grid_uv[*]=0
    status_str.weights_uv[*]=0
    status_str.grid_uv_model[*]=0
ENDIF
IF Keyword_Set(snapshot_recalculate) THEN BEGIN
    status_str.healpix_cube[*]=0
    status_str.hpx_even[*]=0
    status_str.hpx_odd[*]=0
ENDIF
    
IF Keyword_Set(force_data) THEN BEGIN
    status_str.hdr=0
    status_str.obs=0
    status_str.params=0
    status_str.psf=0
    status_str.antenna=0
    status_str.jones=0
    status_str.cal=0
    status_str.flag_arr=0
    status_str.autos=0
    status_str.vis[*]=0
    status_str.vis_model[*]=0
    status_str.grid_uv[*]=0
    status_str.weights_uv[*]=0
    status_str.grid_uv_model[*]=0
    data_flag=0
ENDIF
IF Keyword_Set(force_no_data) THEN data_flag=1

fhd_save_io,status_str,file_path_fhd=file_path_fhd,var='status_str',/force_set,/text
RETURN,data_flag
END