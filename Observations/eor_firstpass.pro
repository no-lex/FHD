PRO eor_firstpass,cleanup=cleanup,ps_export=ps_export,recalculate_all=recalculate_all,export_images=export_images,version=version,$
    beam_recalculate=beam_recalculate,healpix_recalculate=healpix_recalculate,mapfn_recalculate=mapfn_recalculate,$
    grid=grid,deconvolve=deconvolve,channel=channel,output_directory=output_directory,show_obsname=show_obsname,$
    julian_day=julian_day,uvfits_version=uvfits_version,uvfits_subversion=uvfits_subversion,vis_baseline_hist=vis_baseline_hist,_Extra=extra
except=!except
!except=0 
heap_gc
;wrapper designed to generate decent images as quickly as possible

calibration_visibilities_subtract=1
calibrate_visibilities=1
IF N_Elements(recalculate_all) EQ 0 THEN recalculate_all=0
IF N_Elements(export_images) EQ 0 THEN export_images=1
IF N_Elements(cleanup) EQ 0 THEN cleanup=1
IF N_Elements(ps_export) EQ 0 THEN ps_export=0
IF N_Elements(version) EQ 0 THEN version=1
IF N_Elements(deconvolve) EQ 0 THEN deconvolve=0
IF N_Elements(mapfn_recalculate) THEN mapfn_recalculate=0
IF N_Elements(healpix_recalculate) EQ 0 THEN healpix_recalculate=0
IF N_Elements(flag_visibilities) EQ 0 THEN flag_visibilities=1
IF N_Elements(julian_day) EQ 0 THEN julian_day=2456528
IF N_Elements(uvfits_version) EQ 0 THEN uvfits_version=2
IF N_Elements(uvfits_subversion) EQ 0 THEN uvfits_subversion=0
IF N_Elements(vis_baseline_hist) EQ 0 THEN vis_baseline_hist=1
IF N_Elements(show_obsname) EQ 0 THEN show_obsname=1
image_filter_fn='filter_uv_uniform' ;applied ONLY to output images

;NEED TO FIGURE OUT THE PROPER DIRECTORY AND output_directory TO USE AT MIT
data_directory='/nfs/mwa-09/r1/EoRuvfits/jd'+strtrim(julian_day,2)+'v'+strtrim(uvfits_version,2)+'_'+strtrim(uvfits_subversion,2)
output_directory='/nfs/mwa-09/r1/djc/EoR2013/Aug23/'

vis_file_list=file_search(data_directory,'*.uvfits',count=n_files)
fhd_file_list=fhd_path_setup(vis_file_list,version=version,output_directory=output_directory,_Extra=extra)
healpix_path=fhd_path_setup(output_dir=output_directory,subdir='Healpix',output_filename='Combined_obs',version=version,_Extra=extra)
catalog_file_path=filepath('MRC_full_radio_catalog.fits',root=rootdir('FHD'),subdir='catalog_data')
;calibration_catalog_file_path=filepath('mwa_calibration_source_list.sav',root=rootdir('FHD'),subdir='catalog_data')
;calibration_catalog_file_path=filepath('eor1_calibration_source_list.sav',root=rootdir('FHD'),subdir='catalog_data')
;calibration_catalog_file_path=filepath('mwa_calibration_source_list_nofornax.sav',root=rootdir('FHD'),subdir='catalog_data')
calibration_catalog_file_path=filepath('eor01_calibration_source_list.sav',root=rootdir('FHD'),subdir='catalog_data')

dimension=2048.
max_sources=0
pad_uv_image=2.
FoV=100.
no_ps=1 ;don't save postscript copy of images
psf_dim=10
min_baseline=1.
flag_nsigma=20.
ring_radius=6.*pad_uv_image
nfreq_avg=16
max_calibration_sources=300.
weights_grid=0
psf_resolution=8.
no_rephase=1 ;set to use obsra, obsdec for phase center even if phasera, phasedec present in a .metafits file

general_obs,cleanup=cleanup,ps_export=ps_export,recalculate_all=recalculate_all,export_images=export_images,version=version,$
    beam_recalculate=beam_recalculate,healpix_recalculate=healpix_recalculate,mapfn_recalculate=mapfn_recalculate,$
    grid=grid,deconvolve=deconvolve,image_filter_fn=image_filter_fn,data_directory=data_directory,output_directory=output_directory,$
    vis_file_list=vis_file_list,fhd_file_list=fhd_file_list,healpix_path=healpix_path,catalog_file_path=catalog_file_path,$
    dimension=dimension,max_sources=max_sources,pad_uv_image=pad_uv_image,psf_dim=psf_dim,$
    FoV=FoV,no_ps=no_ps,min_baseline=min_baseline,flag_visibilities=flag_visibilities,flag_calibration=flag_calibration,$
    calibrate_visibilities=calibrate_visibilities,calibration_catalog_file_path=calibration_catalog_file_path,$
    ring_radius=ring_radius,flag_nsigma=flag_nsigma,nfreq_avg=nfreq_avg,max_calibration_sources=max_calibration_sources,$
    calibration_visibilities_subtract=calibration_visibilities_subtract,weights_grid=weights_grid,/mark_zenith,$
    vis_baseline_hist=vis_baseline_hist,psf_resolution=psf_resolution,no_rephase=no_rephase,show_obsname=show_obsname,_Extra=extra
!except=except
END