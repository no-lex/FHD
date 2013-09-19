
;+
; :Description:
;    uvfits2fhd is the main program for working with uvfits data. 
;    It will read the uvfits file, grid the data, generate the holographic mapping functions, 
;    and run Fast Holographic Deconvolution
;
;
;
; :Keywords:
;    data_directory - working directory
;    
;    filename - uvfits filename, omitting the .uvfits extension. 
;       If the data is already calibrated, it should end with _cal.uvfits instead of just .uvfits
;    
;    beam_recalculate - if set, generates a new beam model
;    
;    mapfn_recalculate - if not set to 0, will generate Holographic Mapping Functions for each polarization
;    
;    dimension - desired dimension in pixels of the final images
;    
;    kbinsize - pixel size in wavelengths of the uv image. 
;    
;    n_pol - 1: use xx only, 2: use xx and xy, 4: use xx, yy, xy, and yx (Default: as many as are available)
;    
;    flag - set to look for anomalous visibility data and update flags 
;       (default=1, also set to 1 if '_flags.sav' does not exist)
;    
;    Extra - pass any non-default parameters to fast_holographic_deconvolution through this parameter 
;
; :Author: isullivan 2012
;-
PRO uvfits2fhd,file_path_vis,export_images=export_images,cleanup=cleanup,$
    beam_recalculate=beam_recalculate,mapfn_recalculate=mapfn_recalculate,grid_recalculate=grid_recalculate,$
    n_pol=n_pol,flag=flag,silent=silent,GPU_enable=GPU_enable,deconvolve=deconvolve,transfer_mapfn=transfer_mapfn,$
    rephase_to_zenith=rephase_to_zenith,healpix_recalculate=healpix_recalculate,tile_flag_list=tile_flag_list,$
    file_path_fhd=file_path_fhd,force_data=force_data,force_no_data=force_no_data,freq_start=freq_start,freq_end=freq_end,$
    calibrate_visibilities=calibrate_visibilities,transfer_calibration=transfer_calibration,error=error,$
    calibration_catalog_file_path=calibration_catalog_file_path,quickview=quickview,$
    calibration_image_subtract=calibration_image_subtract,calibration_visibilities_subtract=calibration_visibilities_subtract,$
    no_rephase=no_rephase,_Extra=extra

compile_opt idl2,strictarrsubs    
except=!except
!except=0 ;System variable that controls when math errors are printed. Set to 0 to disable.
error=0
heap_gc 
t0=Systime(1)
;IF N_Elements(version) EQ 0 THEN version=0
IF N_Elements(calibrate_visibilities) EQ 0 THEN calibrate_visibilities=0
IF N_Elements(beam_recalculate) EQ 0 THEN beam_recalculate=1
IF N_Elements(mapfn_recalculate) EQ 0 THEN mapfn_recalculate=1
IF N_Elements(grid_recalculate) EQ 0 THEN grid_recalculate=1
IF N_Elements(healpix_recalculate) EQ 0 THEN healpix_recalculate=0
IF N_Elements(flag) EQ 0 THEN flag=0.
IF N_Elements(transfer_mapfn) EQ 0 THEN transfer_mapfn=0

;IF N_Elements(GPU_enable) EQ 0 THEN GPU_enable=0
;IF Keyword_Set(GPU_enable) THEN BEGIN
;    Defsysv,'GPU',exist=gpuvar_exist
;    IF gpuvar_exist eq 0 THEN GPUinit
;    IF !GPU.mode NE 1 THEN GPU_enable=0
;ENDIF

print,'Deconvolving: ',file_path_vis
print,systime()
print,'Output file_path:',file_path_fhd
ext='.uvfits'
fhd_dir=file_dirname(file_path_fhd)
basename=file_basename(file_path_fhd)
header_filepath=file_path_fhd+'_header.sav'
flags_filepath=file_path_fhd+'_flags.sav'
;vis_filepath=file_path_fhd+'_vis.sav'
obs_filepath=file_path_fhd+'_obs.sav'
params_filepath=file_path_fhd+'_params.sav'
hdr_filepath=file_path_fhd+'_hdr.sav'
fhd_filepath=file_path_fhd+'_fhd.sav'
autocorr_filepath=file_path_fhd+'_autos.sav'
cal_filepath=file_path_fhd+'_cal.sav'
IF N_Elements(deconvolve) EQ 0 THEN IF file_test(fhd_filepath) EQ 0 THEN deconvolve=1
;IF Keyword_Set(export_images) THEN IF file_test(file_path_fhd+'_fhd.sav') EQ 0 THEN deconvolve=1

pol_names=['xx','yy','xy','yx','I','Q','U','V']

IF Keyword_Set(n_pol) THEN n_pol1=n_pol ELSE n_pol1=1
test_mapfn=1 & FOR pol_i=0,n_pol1-1 DO test_mapfn*=file_test(file_path_fhd+'_uv_'+pol_names[pol_i]+'.sav')
IF test_mapfn EQ 0 THEN grid_recalculate=1
test_mapfn=1 & FOR pol_i=0,n_pol1-1 DO test_mapfn*=file_test(file_path_fhd+'_mapfn_'+pol_names[pol_i]+'.sav')
IF Keyword_Set(transfer_mapfn) THEN BEGIN
    IF size(transfer_mapfn,/type) NE 7 THEN transfer_mapfn=basename
    IF basename NE transfer_mapfn THEN BEGIN
        mapfn_recalculate=0
        test_mapfn=1
    ENDIF
ENDIF
IF test_mapfn EQ 0 THEN IF Keyword_Set(deconvolve) THEN mapfn_recalculate=(grid_recalculate=1)
IF Keyword_Set(mapfn_recalculate) THEN grid_recalculate=1

data_flag=file_test(hdr_filepath) AND file_test(flags_filepath) AND file_test(obs_filepath) AND file_test(params_filepath)

IF Keyword_Set(beam_recalculate) OR Keyword_Set(grid_recalculate) OR $
    Keyword_Set(mapfn_recalculate) OR not data_flag THEN data_flag=1 ELSE data_flag=0

IF Keyword_Set(force_data) THEN data_flag=1
IF Keyword_Set(force_no_data) THEN data_flag=0

IF Keyword_Set(data_flag) THEN BEGIN
    IF file_test(file_path_vis) EQ 0 THEN BEGIN
        print,"File: "+file_path_vis+" not found! Returning"
        error=1
        RETURN
    ENDIF
    data_struct=mrdfits(file_path_vis,0,data_header0,/silent)
    
    hdr=vis_header_extract(data_header0, params = data_struct.params)    
    params=vis_param_extract(data_struct.params,hdr)
    obs=vis_struct_init_obs(file_path_vis,hdr,params,n_pol=n_pol,_Extra=extra)
    kbinsize=obs.kpix
    degpix=obs.degpix
    dimension=obs.dimension
    pol_dim=hdr.pol_dim
    freq_dim=hdr.freq_dim
    real_index=hdr.real_index
    imaginary_index=hdr.imaginary_index
    flag_index=hdr.flag_index
    n_pol=obs.n_pol
    n_freq=obs.n_freq
    
    data_array=Temporary(data_struct.array[*,0:n_pol-1,*])
    data_struct=0. ;free memory
    
    vis_arr=Ptrarr(n_pol,/allocate)
    flag_arr=Ptrarr(n_pol,/allocate)
    FOR pol_i=0,n_pol-1 DO BEGIN
        *vis_arr[pol_i]=Complex(reform(data_array[real_index,pol_i,*,*]),$
            Reform(data_array[imaginary_index,pol_i,*,*]));*phase_shift
        *flag_arr[pol_i]=reform(data_array[flag_index,pol_i,*,*])
    ENDFOR
    ;free memory
    data_array=0 
    flag_arr0=0
;    IF not Keyword_Set(no_rephase) THEN IF (obs.phasera NE obs.obsra) OR (obs.phasedec NE obs.obsdec) THEN $
;        vis_arr=visibility_rephase(obs,params,vis_arr)
    
    IF Tag_exist(obs,'freq') THEN freq_arr=obs.freq ELSE freq_arr=(*obs.baseline_info).freq
    
    IF Keyword_Set(freq_start) THEN bw_start=(freq_start*1E6)>Min(freq_arr) ELSE bw_start=Min(freq_arr)
    IF Keyword_Set(freq_end) THEN bw_end=(freq_end*1E6)<Max(freq_arr) ELSE bw_end=Max(freq_arr)
    bandwidth=Round((bw_end-bw_start)/1E5)/10.
    fov=dimension*degpix
    k_span=kbinsize*dimension
    
    print,String(format='("Image size used: ",A," pixels")',Strn(dimension))
    print,String(format='("Image resolution used: ",A," degrees/pixel")',Strn(degpix))
    print,String(format='("Approx. beam area: ",A," pixels")',Strn((!RaDeg/(obs.MAX_BASELINE/obs.KPIX)/obs.degpix)))
    print,String(format='("Field of view used: ",A," degrees")',Strn(fov))
    print,String(format='("Frequency range: ",A,"-",A," MHz")',Strn(Round((bw_start)/1E5)/10.),Strn(Round((bw_end)/1E5)/10.))
    print,String(format='("UV resolution used: ",A," wavelengths/pixel")',Strn(kbinsize))
    print,String(format='("UV image size used: ",A," wavelengths")',Strn(k_span))
    print,String(format='("Min baseline: ",A," wavelengths")',Strn(obs.min_baseline))
    print,String(format='("Max baseline: ",A," wavelengths")',Strn(obs.max_baseline))
    print,String(format='("Observation pointing (Az,El): ",A," ",A)',$
        Strn(obs.obsaz,length=6),Strn(obs.obsalt,length=5))
    IF Ptr_valid(obs.delays) THEN print,String(format='("Beamformer settings: ",(I))',*obs.delays)
    print,String(format='("Observation coordinates: ",A," ",A,A)',$
        Strn(obs.obsra,length=7),(obs.obsdec GE 0) ? '+':'-',Strn(Abs(obs.obsdec),length=6))
    print,String(format='("Zenith coordinates: ",A," ",A,A)',$
        Strn(obs.zenra,length=7),(obs.zendec GE 0) ? '+':'-',Strn(Abs(obs.zendec),length=6))
    IF (obs.phasera NE obs.obsra) OR (obs.phasedec NE obs.obsdec) THEN $
        print,String(format='("Image phased to coordinates: ",A," ",A,A)',$
            Strn(obs.phasera,length=7),(obs.phasedec GE 0) ? '+':'-',Strn(Abs(obs.phasedec),length=6))
    
    IF Tag_exist(obs,'alpha') THEN alpha=obs.alpha ELSE alpha=0.
    print,String(format='("Spectral index fit: ",A)',Strn(alpha))
    
    ;Read in or construct a new beam model. Also sets up the structure PSF
    print,'Calculating beam model'
    psf=beam_setup(obs,file_path_fhd,restore_last=(Keyword_Set(beam_recalculate) ? 0:1),silent=silent,timing=t_beam,_Extra=extra)
    IF Keyword_Set(t_beam) THEN print,'Beam modeling time: ',t_beam
    beam=Ptrarr(n_pol,/allocate)
    FOR pol_i=0,n_pol-1 DO *beam[pol_i]=beam_image(psf,obs,pol_i=pol_i,/fast)>0.
    
;    IF file_test(flags_filepath) AND not Keyword_Set(flag) THEN BEGIN
;        flag_arr=getvar_savefile(flags_filepath,'flag_arr')
;    ENDIF ELSE BEGIN
;        flag_arr=vis_flag_basic(flag_arr,obs,params,n_pol=n_pol,n_freq=n_freq,_Extra=extra)
;    ENDELSE
    
    IF Keyword_Set(freq_start) THEN BEGIN
        frequency_array_MHz=freq_arr/1E6
        freq_start_cut=where(frequency_array_MHz LT freq_start,nf_cut_start)
        IF nf_cut_start GT 0 THEN FOR pol_i=0,n_pol-1 DO *flag_arr[freq_start_cut,*]=0
    ENDIF ELSE nf_cut_start=0
    IF Keyword_Set(freq_end) THEN BEGIN
        frequency_array_MHz=freq_arr/1E6
        freq_end_cut=where(frequency_array_MHz GT freq_end,nf_cut_end)
        IF nf_cut_end GT 0 THEN FOR pol_i=0,n_pol-1 DO *flag_arr[freq_end_cut,*]=0
    ENDIF ELSE nf_cut_end=0
    
    IF Keyword_Set(tile_flag_list) THEN BEGIN
        tile_A=(*obs.baseline_info).tile_A
        tile_B=(*obs.baseline_info).tile_B
        hist_A=histogram(tile_A,min=1,/bin,reverse=ra)
        hist_B=histogram(tile_B,min=1,/bin,reverse=rb)
        hist_C=histogram(tile_flag_list,min=1,/bin,reverse=rc)
        hist_AB=hist_A+hist_B
        n_ab=N_Elements(hist_AB)
        n_c=N_Elements(hist_C)
        n_bin=n_c<n_ab
        tile_cut_i=where((hist_AB[0:n_bin-1] GT 0) AND (hist_C[0:n_bin-1] GT 0),n_cut)
        IF n_cut GT 0 THEN BEGIN
            FOR ci=0,n_cut-1 DO BEGIN
                ti=tile_cut_i[ci]
                na=ra[ra[ti+1]-1]-ra[ra[ti]]
                IF na GT 0 THEN FOR pol_i=0,n_pol-1 DO *flag_arr[*,ra[ra[ti]:ra[ti+1]-1]]=0
                nb=rb[rb[ti+1]-1]-rb[rb[ti]]
                IF nb GT 0 THEN FOR pol_i=0,n_pol-1 DO *flag_arr[*,rb[rb[ti]:rb[ti+1]-1]]=0
            ENDFOR
            SAVE,flag_arr,filename=flags_filepath,/compress
        ENDIF
    ENDIF
    
    vis_count_i=where(*flag_arr[0],n_vis_in)
    obs.n_vis_in=n_vis_in
    
    IF Keyword_Set(transfer_calibration) THEN BEGIN
        calibrate_visibilities=1
        IF size(transfer_calibration,/type) LT 7 THEN transfer_calibration=cal_filepath
    ENDIF
    
    IF Keyword_Set(calibrate_visibilities) THEN BEGIN
        print,"Calibrating visibilities"
        IF not Keyword_Set(transfer_calibration) AND not Keyword_Set(calibration_source_list) THEN $
            calibration_source_list=generate_source_cal_list(obs,psf,catalog_path=calibration_catalog_file_path,_Extra=extra)
        
        IF Keyword_Set(calibration_visibilities_subtract) THEN calibration_image_subtract=0
        IF Keyword_Set(calibration_image_subtract) THEN return_cal_model=1
        vis_arr=vis_calibrate(vis_arr,cal,obs,psf,params,flag_ptr=flag_arr,file_path_fhd=file_path_fhd,$
             transfer_calibration=transfer_calibration,timing=cal_timing,error=error,model_uv_arr=model_uv_arr,$
             calibration_source_list=calibration_source_list,return_cal_model=return_cal_model,$
             calibration_visibilities_subtract=calibration_visibilities_subtract,silent=silent,_Extra=extra)
        print,String(format='("Calibration timing: ",A)',Strn(cal_timing))
        save,cal,filename=cal_filepath,/compress
        IF Keyword_Set(return_cal_model) THEN save,model_uv_arr,filename=file_path_fhd+'_cal_uv.sav'
    ENDIF
    
    IF Keyword_Set(transfer_mapfn) THEN BEGIN
        flag_arr1=flag_arr
        IF basename EQ transfer_mapfn THEN BEGIN 
            IF Keyword_Set(flag) THEN BEGIN
                print,'Flagging anomalous data'
                vis_flag,vis_arr,flag_arr,obs,params,_Extra=extra
            ENDIF
            
        ENDIF ELSE restore,filepath(transfer_mapfn+'_flags.sav',root=fhd_dir) ;flag_arr
        SAVE,flag_arr,filename=flags_filepath,/compress
        n0=N_Elements(*flag_arr[0])
        n1=N_Elements(*flag_arr1[0])
        IF n1 GT n0 THEN BEGIN
            ;If more data, zero out additional
            nf0=(size(*flag_arr[0],/dimension))[0]
            nb0=(size(*flag_arr[0],/dimension))[1]
            FOR pol_i=0,n_pol-1 DO BEGIN
                *flag_arr1[pol_i]=fltarr(size(*flag_arr1[pol_i],/dimension))
                (*flag_arr1[pol_i])[0:nf0-1,0:nb0-1]*=*flag_arr[pol_i]
            ENDFOR
            flag_arr=flag_arr1
            SAVE,flag_arr,filename=flags_filepath,/compress
        ENDIF
        IF n0 GT n1 THEN BEGIN
            ;If less data, return with an error!
            error=1
            RETURN
        ENDIF
;        CASE 1 OF
;            n0 EQ n1:FOR pol_i=0,n_pol-1 DO *flag_arr1[pol_i]*=*flag_arr[pol_i] ;in case using different # of pol's
;            n1 GT n0: BEGIN
;                nf0=(size(*flag_arr[0],/dimension))[0]
;                nb0=(size(*flag_arr[0],/dimension))[1]
;                FOR pol_i=0,n_pol-1 DO (*flag_arr1[pol_i])[0:nf0-1,0:nb0-1]*=*flag_arr[pol_i]
;            END
;            ELSE: BEGIN
;                nf1=(size(*flag_arr1[0],/dimension))[0]
;                nb1=(size(*flag_arr1[0],/dimension))[1]
;                print,"WARNING: restoring flags and Mapfn from mismatched data! Mapfn may be corrupted!"
;                FOR pol_i=0,n_pol-1 DO *flag_arr1[pol_i]*=(*flag_arr[pol_i])[0:nf1-1,0:nb1-1]
;            ENDELSE
;        ENDCASE
;        flag_arr=flag_arr
;        SAVE,flag_arr,filename=flags_filepath,/compress
;        flag_arr1=0
    ENDIF ELSE BEGIN
        IF Keyword_Set(flag) THEN BEGIN
            print,'Flagging anomalous data'
            vis_flag,vis_arr,flag_arr,obs,params,_Extra=extra
            SAVE,flag_arr,filename=flags_filepath,/compress
        ENDIF ELSE $ ;saved flags are needed for some later routines, so save them even if no additional flagging is done
            SAVE,flag_arr,filename=flags_filepath,/compress
    ENDELSE
    
    flag_freq_test=fltarr(obs.n_freq)
    flag_tile_test=fltarr(obs.n_tile)
    FOR pol_i=0,n_pol-1 DO flag_freq_test+=Max(*flag_arr[pol_i],dimension=2)>0
    flag_freq_use_i=where(flag_freq_test,n_freq_use,ncomp=n_freq_cut)
    IF n_freq_use EQ 0 THEN print,'All frequencies flagged!' ELSE BEGIN
        (*obs.baseline_info).freq_use[*]=0
        (*obs.baseline_info).freq_use[flag_freq_use_i]=1
    ENDELSE
    tile_A=(*obs.baseline_info).tile_A
    tile_B=(*obs.baseline_info).tile_B
    FOR pol_i=0,n_pol-1 DO BEGIN
        FOR tile_i=0,obs.n_tile-1 DO BEGIN
            tA_i=where(tile_A EQ (tile_i+1),nA)
            tB_i=where(tile_B EQ (tile_i+1),nB)
            
            IF nA GT 0 THEN flag_tile_test[tile_i]+=Max((*flag_arr[pol_i])[*,tA_i])>0
            IF nB GT 0 THEN flag_tile_test[tile_i]+=Max((*flag_arr[pol_i])[*,tB_i])>0
        ENDFOR
    ENDFOR
    flag_tile_use_i=where(flag_tile_test,n_tile_use,ncomp=n_tile_cut)
    IF n_tile_use EQ 0 THEN print,'All tiles flagged!' ELSE BEGIN
        (*obs.baseline_info).tile_use[*]=0
        (*obs.baseline_info).tile_use[flag_tile_use_i]=1
    ENDELSE
    print,String(format='(A," frequency channels used and ",A," in-band channels flagged")',$
        Strn(n_freq_use),Strn(n_freq_cut-nf_cut_end-nf_cut_start))
    print,String(format='(A," tiles used and ",A," tiles flagged")',$
        Strn(n_tile_use),Strn(n_tile_cut))
    
    SAVE,obs,filename=obs_filepath,/compress
    SAVE,params,filename=params_filepath,/compress
    SAVE,hdr,filename=hdr_filepath,/compress
        
    vis_flag_update,flag_arr,obs,psf,params,file_path_fhd,fi_use=fi_use,_Extra=extra
    SAVE,obs,filename=obs_filepath,/compress
    fhd_log_settings,file_path_fhd,obs=obs,psf=psf,cal=cal
    
    IF obs.n_vis EQ 0 THEN BEGIN
        print,"All data flagged! Returning."
        error=1
        RETURN
    ENDIF
    
    IF Keyword_Set(healpix_recalculate) THEN $
        hpx_cnv=healpix_cnv_generate(obs,file_path_fhd=file_path_fhd,nside=nside,$
            mask=beam_mask,radius=radius,restore_last=0,_Extra=extra)
    hpx_cnv=0
    
    autocorr_i=where(tile_A EQ tile_B,n_autocorr)
    auto_corr=Ptrarr(n_pol)
    IF n_autocorr GT 0 THEN FOR pol_i=0,n_pol-1 DO BEGIN
        auto_vals=(*vis_arr[pol_i])[*,autocorr_i]
        auto_corr[pol_i]=Ptr_new(auto_vals)
    ENDFOR
    SAVE,auto_corr,obs,filename=autocorr_filepath,/compress
    
    beam_mask=fltarr(obs.dimension,obs.elements)+1
    alias_mask=fltarr(obs.dimension,obs.elements) 
    alias_mask[obs.dimension/4:3.*obs.dimension/4.,obs.elements/4:3.*obs.elements/4.]=1
    FOR pol_i=0,(n_pol<2)-1 DO BEGIN
        mask0=fltarr(obs.dimension,obs.elements)
        mask_i=where(*beam[pol_i]*alias_mask GE 0.05)
        mask0[mask_i]=1
        beam_mask*=mask0
    ENDFOR
    
    t_grid=fltarr(n_pol)
    t_mapfn_gen=fltarr(n_pol)
    
    ;Grid the visibilities
    IF Keyword_Set(grid_recalculate) THEN BEGIN
        print,'Gridding visibilities'
        IF Keyword_Set(deconvolve) THEN map_fn_arr=Ptrarr(n_pol,/allocate)
        image_arr=Ptrarr(n_pol,/allocate)
        image_uv_arr=Ptrarr(n_pol,/allocate)
        weights_arr=Ptrarr(n_pol,/allocate)
        FOR pol_i=0,n_pol-1 DO BEGIN
    ;        IF Keyword_Set(GPU_enable) THEN $
    ;            dirty_UV=visibility_grid_GPU(*vis_arr[pol_i],*flag_arr[pol_i],obs,psf,params,timing=t_grid0,$
    ;                polarization=pol_i,weights=weights_grid,silent=silent,mapfn_recalculate=mapfn_recalculate) $
    ;        ELSE $
            weights_grid=1 ;initialize
            
            IF Keyword_Set(cleanup) THEN IF cleanup GT 0 THEN no_save=1
            dirty_UV=visibility_grid(vis_arr[pol_i],flag_arr[pol_i],obs,psf,params,file_path_fhd,$
                timing=t_grid0,fi_use=fi_use,polarization=pol_i,weights=weights_grid,silent=silent,$
                mapfn_recalculate=mapfn_recalculate,return_mapfn=return_mapfn,error=error,no_save=no_save,_Extra=extra)
            IF Keyword_Set(error) THEN RETURN
            t_grid[pol_i]=t_grid0
            dirty_img=dirty_image_generate(dirty_UV,baseline_threshold=0,degpix=degpix)
            SAVE,dirty_UV,weights_grid,filename=file_path_fhd+'_uv_'+pol_names[pol_i]+'.sav',/compress
            SAVE,dirty_img,filename=file_path_fhd+'_dirty_'+pol_names[pol_i]+'.sav',/compress

            IF Keyword_Set(deconvolve) THEN IF mapfn_recalculate THEN *map_fn_arr[pol_i]=Temporary(return_mapfn)
            *image_arr[pol_i]=Temporary(dirty_img)
            *image_uv_arr[pol_i]=Temporary(dirty_UV)
            *weights_arr[pol_i]=Temporary(weights_grid)
        ENDFOR
        print,'Gridding time:',t_grid
    ENDIF ELSE BEGIN
        print,'Visibilities not re-gridded'
    ENDELSE
    IF (Ptr_valid(vis_arr))[0] THEN Ptr_free,vis_arr
    IF (Ptr_valid(flag_arr))[0] THEN Ptr_free,flag_arr
ENDIF

;deconvolve point sources using fast holographic deconvolution
IF Keyword_Set(deconvolve) THEN BEGIN
    print,'Deconvolving point sources'
    fhd_wrap,obs,params,psf,fhd,cal,file_path_fhd=file_path_fhd,_Extra=extra,silent=silent,calibration_image_subtract=calibration_image_subtract,$
        transfer_mapfn=transfer_mapfn,map_fn_arr=map_fn_arr,image_uv_arr=image_uv_arr,weights_arr=weights_arr,model_uv_arr=model_uv_arr
ENDIF ELSE BEGIN
    print,'Gridded visibilities not deconvolved'
    IF Keyword_Set(quickview) THEN fhd_quickview,file_path_fhd=file_path_fhd,_Extra=extra
ENDELSE
;Generate fits data files and images
IF Keyword_Set(export_images) THEN BEGIN
    print,'Exporting images'    
    fhd_output,obs,fhd,file_path_fhd=file_path_fhd,map_fn_arr=map_fn_arr,silent=silent,transfer_mapfn=transfer_mapfn,$
        image_uv_arr=image_uv_arr,weights_arr=weights_arr,beam_arr=beam,_Extra=extra
ENDIF

IF N_Elements(map_fn_arr) GT 0 THEN IF Max(Ptr_valid(map_fn_arr)) THEN Ptr_free,map_fn_arr
;;generate images showing the uv contributions of each tile. Very helpful for debugging!
;print,'Calculating individual tile uv coverage'
;mwa_tile_locate,obs=obs,params=params,psf=psf
timing=Systime(1)-t0
print,'Full pipeline time (minutes): ',Strn(Round(timing/60.))
print,''
!except=except
END