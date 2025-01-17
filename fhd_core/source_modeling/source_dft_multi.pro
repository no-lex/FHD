PRO source_dft_multi,obs,jones,source_array,model_uv_full,spectral_uv_full,xvals=xvals,yvals=yvals,uv_i_use=uv_i_use,$
    conserve_memory=conserve_memory,frequency=frequency,dft_threshold=dft_threshold,silent=silent,$
    dimension=dimension,elements=elements,n_pol=n_pol,spectral_model_uv_arr=spectral_model_uv_arr,$
    n_spectral=n_spectral,flatten_spectrum=flatten_spectrum,double_precision=double_precision,$
    gaussian_source_models = gaussian_source_models,_Extra=extra

alpha_corr=0.
IF Keyword_Set(obs) THEN BEGIN
    IF N_Elements(dft_threshold) EQ 0 THEN dft_threshold=obs.dft_threshold
    dimension=obs.dimension
    elements=obs.elements
    n_pol=obs.n_pol
    IF N_Elements(n_spectral) EQ 0 THEN n_spectral=obs.degrid_spectral_terms
    IF Keyword_Set(flatten_spectrum) THEN alpha_corr=obs.alpha
    IF Tag_Exist(obs, 'double_precision') THEN double_precision=obs.double_precision ELSE double_precision=0
ENDIF ELSE BEGIN
    IF N_Elements(dft_threshold) EQ 0 THEN dft_threshold=0.
    IF N_Elements(elements) EQ 0 THEN elements=dimension
    IF N_Elements(n_pol) EQ 0 THEN n_pol=1
    IF N_Elements(n_spectral) EQ 0 THEN n_spectral=0
    IF Keyword_Set(flatten_spectrum) THEN print,"WARNING: obs structure not present in source_dft_multi, but flatten_spectrum was set"
    IF N_Elements(double_precision) EQ 0 THEN double_precision=0
ENDELSE


dft_edge_pix = Floor((dimension<elements)/8)
IF N_Elements(uv_i_use) EQ 0 THEN uv_i_use=Lindgen(dimension*elements)

IF N_Elements(xvals) NE N_Elements(uv_i_use) THEN xvals=(meshgrid(dimension,elements,1))[uv_i_use]-dimension/2
IF N_Elements(yvals) NE N_Elements(uv_i_use) THEN yvals=(meshgrid(dimension,elements,2))[uv_i_use]-elements/2

x_vec=source_array.x
y_vec=source_array.y

;set /no_extend since extended sources will not be read. 
; If you want extended sources, inflate the source list before calling this program
source_array_use=Stokes_cnv(source_array,jones,/inverse,/no_extend,_Extra=extra) 
n_source=N_Elements(source_array)

frequency=obs.freq_center
freq_ref=Mean(source_array.freq)
freq_ratio=Abs(Alog10(freq_ref/frequency)) ;it often happens that one is in Hz and the other in MHz. Assuming no one will ever want to extrapolate more than two orders of magnitude, correct any huge mismatch
IF freq_ratio GT 2 THEN freq_scale=10.^(Round(Alog10(freq_ref/frequency)/3.)*3.) ELSE freq_scale=1.
frequency_use=frequency*freq_scale

alpha_i=where(source_array.alpha,n_alpha) ;find sources with non-zero spectral indices
FOR a_i=0L,n_alpha-1 DO BEGIN
    flux_scale=(frequency_use/freq_ref)^source_array[alpha_i[a_i]].alpha
    FOR pol_i=0,n_pol-1 DO source_array_use[alpha_i[a_i]].flux.(pol_i)*=flux_scale
ENDFOR

IF keyword_set(gaussian_source_models) then begin
  if tag_exist(source_array, 'shape') then begin
    gaussian_ra=make_array(n_elements(source_array),/double)
    gaussian_dec=make_array(n_elements(source_array),/double)
    gaussian_rot=make_array(n_elements(source_array),/double)
    for source_ind=0,n_elements(source_array)-1 do begin
      if tag_exist(source_array[source_ind], 'shape') then begin
        ;Convert from FWHM in arcsec to stddev in deg
        gaussian_ra[source_ind]=source_array[source_ind].shape.x/(7200*sqrt(2*alog(2)))
        gaussian_dec[source_ind]=source_array[source_ind].shape.y/(7200*sqrt(2*alog(2)))
        ;Convert from deg to rad
        gaussian_rot[source_ind]=source_array[source_ind].shape.angle*!Pi/180.
      endif else begin
        gaussian_ra[source_ind]=0
        gaussian_dec[source_ind]=0
        gaussian_rot[source_ind]=0
      endelse
    endfor
    inds_gauss=where(gaussian_ra,n_gauss_params,complement=inds_point)
    if n_gauss_params eq 0 then begin
      print, 'Catalog does not contain Gaussian shape parameters. Unsetting keyword gaussian_source_models.'
      undefine, gaussian_source_models
    endif else begin

      ;Gaussian source model major and minor axes RA DEC
      ;           _ a_2,d_2
      ;          / \
      ; a_3,d_3 |   | a_1,d_1
      ;          \_/
      ;   a_4,d_4
      ;
      ;Convert from deg to pixels
      ;Assumption: the RA/DEC of the gaussian can be approximated in a xy coord system where RA->x and DEC->y. DEC translates
      ;well to xy coords, but RA does not, especially near celestial poles.
      gaussian_ra_angular = acos(cos(gaussian_ra*!Dpi/180)/cos(source_array.dec*!Dpi/180)^2 - tan(source_array.dec*!Dpi/180)^2) * 180/!Dpi
      gaussian_ra_vals = [[source_array.ra+.5*gaussian_ra_angular*cos(gaussian_rot)], [source_array.ra-.5*gaussian_dec*sin(gaussian_rot)], $
        [source_array.ra-.5*gaussian_ra_angular*cos(gaussian_rot)], [source_array.ra+.5*gaussian_dec*sin(gaussian_rot)]]
      gaussian_dec_vals = [[source_array.dec+.5*gaussian_ra_angular*sin(gaussian_rot)], [source_array.dec+.5*gaussian_dec*cos(gaussian_rot)], $
        [source_array.dec-.5*gaussian_ra_angular*sin(gaussian_rot)], [source_array.dec-.5*gaussian_dec*cos(gaussian_rot)]]
      undefine, gaussian_ra, gaussian_ra_angular, gaussian_dec

      ;Curved sky gaussian widths in pixel coords
      apply_astrometry, obs, x_arr=gaussian_x_vals, y_arr=gaussian_y_vals, ra_arr=gaussian_ra_vals, dec_arr=gaussian_dec_vals, /ad2xy
      gaussian_x = sqrt((gaussian_x_vals[*,0]-gaussian_x_vals[*,2])^2+(gaussian_y_vals[*,0]-gaussian_y_vals[*,2])^2)
      gaussian_y = sqrt((gaussian_x_vals[*,1]-gaussian_x_vals[*,3])^2+(gaussian_y_vals[*,1]-gaussian_y_vals[*,3])^2)

      ;Flat sky gaussian widths in pixel coords
      flat_sky_gaussian_x = sqrt((gaussian_ra_vals[*,0]-gaussian_ra_vals[*,2])^2+(gaussian_dec_vals[*,0]-gaussian_dec_vals[*,2])^2)/obs.degpix
      flat_sky_gaussian_y = sqrt((gaussian_ra_vals[*,1]-gaussian_ra_vals[*,3])^2+(gaussian_dec_vals[*,1]-gaussian_dec_vals[*,3])^2)/obs.degpix
      undefine, gaussian_ra_vals, gaussian_dec_vals    

      ;Projection effect on total integrated flux *in uv-space only*
      flux_factor = (gaussian_x*gaussian_y)/(flat_sky_gaussian_x*flat_sky_gaussian_y)
      FOR pol_i=0,n_pol-1 DO BEGIN
          source_array_use[inds_gauss].flux.(pol_i)*=flux_factor[inds_gauss]
      ENDFOR
      gaussian_x[inds_point]=0
      gaussian_y[inds_point]=0
      undefine, flux_factor, flat_sky_gaussian_x, flat_sky_gaussian_y

    endelse
  endif else begin
    print, 'Catalog does not contain Gaussian shape parameters. Unsetting keyword gaussian_source_models.'
    undefine, gaussian_source_models
  endelse
ENDIF

IF ~keyword_set(gaussian_source_models) THEN BEGIN
    ;Set all gaussian params to be 0
    gaussian_x=make_array(n_elements(source_array),/double)
    gaussian_y=make_array(n_elements(source_array),/double)
    gaussian_rot=make_array(n_elements(source_array),/double)
ENDIF

IF Keyword_Set(n_spectral) THEN BEGIN
;obs.degrid_info is set up in fhd_struct_init_obs. It is turned on by setting the keyword degrid_nfreq_avg
    IF not Keyword_Set(silent) THEN print,"Gridding source model cube using taylor expansion of order: "+Strn(n_spectral)
    alpha_arr=source_array.alpha-alpha_corr
    
    flux_arr=Ptrarr(n_pol,n_spectral+1)
    FOR pol_i=0,n_pol-1 DO BEGIN
        flux_arr[pol_i,0]=Ptr_new(source_array_use.flux.(pol_i))
        FOR s_i=1L,n_spectral DO flux_arr[pol_i,s_i]=Ptr_new(source_array_use.flux.(pol_i)*alpha_arr^s_i)
    ENDFOR
    
    IF Keyword_Set(dft_threshold) THEN BEGIN
        model_uv_arr=Ptrarr(n_pol,n_spectral+1)
        edge_i = where((x_vec LT dft_edge_pix) OR (y_vec LT dft_edge_pix) OR (dimension-x_vec LT dft_edge_pix) OR (elements-y_vec LT dft_edge_pix) OR $
            gaussian_x OR gaussian_y,n_edge_pix, complement=center_pix_i, ncomplement=n_center_pix)
        IF n_edge_pix GT 0 THEN BEGIN
            IF N_Elements(conserve_memory) EQ 0 THEN conserve_memory=1
            model_uv_vals=source_dft(x_vec,y_vec,xvals,yvals,dimension=dimension,elements=elements,flux=flux_arr,$
                conserve_memory=conserve_memory,silent=silent,inds_use=edge_i,double_precision=double_precision,$
                gaussian_source_models=gaussian_source_models, gaussian_x=gaussian_x[edge_i], gaussian_y=gaussian_y[edge_i], $
                gaussian_rot=gaussian_rot[edge_i])
            FOR pol_i=0,n_pol-1 DO BEGIN
                FOR s_i=0L,n_spectral DO BEGIN ;no "-1" for second loop!
                    single_uv=Complexarr(dimension,elements)
                    single_uv[uv_i_use]=*model_uv_vals[pol_i,s_i] 
                    model_uv_arr[pol_i,s_i]=Ptr_new(single_uv,/no_copy)
                ENDFOR
            ENDFOR
        ENDIF
        IF n_center_pix GT 0 THEN BEGIN
            model_uv_arr2=fast_dft(x_vec,y_vec,dimension=dimension,elements=elements,flux_arr=flux_arr,return_kernel=return_kernel,$
                silent=silent,dft_threshold=dft_threshold,inds_use=center_pix_i,double_precision=double_precision)
            FOR i=0L,N_Elements(model_uv_arr)-1 DO BEGIN
                IF Ptr_valid(model_uv_arr[i]) THEN *model_uv_arr[i]+=*model_uv_arr2[i] $
                    ELSE model_uv_arr[i]=Ptr_new(*model_uv_arr2[i])
            ENDFOR
            Ptr_free,model_uv_arr2
        ENDIF
        IF not Keyword_Set(silent) THEN BEGIN
            print,"Center source components using DFT approximation: " + Strn(n_center_pix)
            print,"Edge source components or gaussian components using true DFT: " + Strn(n_edge_pix)
        ENDIF
        Ptr_free,flux_arr
    ENDIF ELSE BEGIN
        IF N_Elements(conserve_memory) EQ 0 THEN conserve_memory=1
        model_uv_vals=source_dft(x_vec,y_vec,xvals,yvals,dimension=dimension,elements=elements,flux=flux_arr,$
            conserve_memory=conserve_memory,silent=silent,double_precision=double_precision,$
            gaussian_source_models=gaussian_source_models, gaussian_x=gaussian_x, gaussian_y=gaussian_y, $
            gaussian_rot=gaussian_rot)
        model_uv_arr=Ptrarr(n_pol,n_spectral+1)
        FOR pol_i=0,n_pol-1 DO BEGIN
            FOR s_i=0L,n_spectral DO BEGIN ;no "-1" for second loop!
                single_uv=Complexarr(dimension,elements)
                single_uv[uv_i_use]=*model_uv_vals[pol_i,s_i] 
                model_uv_arr[pol_i,s_i]=Ptr_new(single_uv,/no_copy)
            ENDFOR
        ENDFOR
        
        Ptr_free,model_uv_vals,flux_arr
    ENDELSE
    
    IF Max(Ptr_valid(model_uv_full)) GT 0 THEN BEGIN
        FOR pol_i=0,n_pol-1 DO *model_uv_full[pol_i]+=Temporary(*model_uv_arr[pol_i,0])
    ENDIF ELSE model_uv_full=model_uv_arr[*,0]
    IF Max(Ptr_valid(spectral_model_uv_arr)) GT 0 THEN BEGIN
        FOR pol_i=0,n_pol-1 DO FOR s_i=0,n_spectral-1 DO $
            *spectral_model_uv_arr[pol_i,s_i]+=Temporary(*model_uv_arr[pol_i,s_i+1])
    ENDIF ELSE spectral_model_uv_arr=model_uv_arr[*,1:*]
    
ENDIF ELSE BEGIN
;in this case, grid one continuum image for each polarization (no frequency dimension)
    IF not Keyword_Set(silent) THEN print,"Gridding source model as single continuum image"
    flux_arr=Ptrarr(n_pol)
    FOR pol_i=0,n_pol-1 DO flux_arr[pol_i]=Ptr_new(source_array_use.flux.(pol_i))
    IF Max(Ptr_valid(model_uv_full)) EQ 0 THEN BEGIN
        model_uv_full=Ptrarr(n_pol,/allocate)
        FOR pol_i=0,n_pol-1 DO *model_uv_full[pol_i]=Complexarr(dimension,elements)
    ENDIF
    IF Keyword_Set(dft_threshold) THEN BEGIN
        model_uv_arr=Ptrarr(n_pol)
        edge_i = where((x_vec LT dft_edge_pix) OR (y_vec LT dft_edge_pix) OR (dimension-x_vec LT dft_edge_pix) OR (elements-y_vec LT dft_edge_pix) OR $
            gaussian_x OR gaussian_y,n_edge_pix, complement=center_pix_i, ncomplement=n_center_pix)
        IF n_edge_pix GT 0 THEN BEGIN
            IF N_Elements(conserve_memory) EQ 0 THEN conserve_memory=1
            model_uv_vals=source_dft(x_vec,y_vec,xvals,yvals,dimension=dimension,elements=elements,flux=flux_arr,$
                conserve_memory=conserve_memory,silent=silent,inds_use=edge_i,double_precision=double_precision,$
                gaussian_source_models=gaussian_source_models, gaussian_x=gaussian_x[edge_i], gaussian_y=gaussian_y[edge_i], $
                gaussian_rot=gaussian_rot[edge_i])
            FOR pol_i=0,n_pol-1 DO BEGIN
                single_uv=Complexarr(dimension,elements)
                single_uv[uv_i_use]=*model_uv_vals[pol_i] 
                model_uv_arr[pol_i]=Ptr_new(single_uv,/no_copy)
            ENDFOR
        ENDIF
        IF n_center_pix GT 0 THEN BEGIN
            model_uv_arr2=fast_dft(x_vec,y_vec,dimension=dimension,elements=elements,flux_arr=flux_arr,return_kernel=return_kernel,$
                silent=silent,dft_threshold=dft_threshold,inds_use=center_pix_i,double_precision=double_precision)
            FOR i=0L,N_Elements(model_uv_arr)-1 DO BEGIN
                IF Ptr_valid(model_uv_arr[i]) THEN *model_uv_arr[i]+=*model_uv_arr2[i] $
                    ELSE model_uv_arr[i]=Ptr_new(*model_uv_arr2[i])
            ENDFOR
            Ptr_free,model_uv_arr2
        ENDIF
        FOR pol_i=0,n_pol-1 DO *model_uv_full[pol_i]+=*model_uv_arr[pol_i]
        IF not Keyword_Set(silent) THEN BEGIN
            print,"Center source components using DFT approximation: " + Strn(n_center_pix)
            print,"Edge source components or gaussian components using true DFT: " + Strn(n_edge_pix)
        ENDIF
        undefine_fhd,model_uv_arr,flux_arr
    ENDIF ELSE BEGIN
        IF N_Elements(conserve_memory) EQ 0 THEN conserve_memory=1
        model_uv_vals=source_dft(x_vec,y_vec,xvals,yvals,dimension=dimension,elements=elements,flux=flux_arr,$
            silent=silent,conserve_memory=conserve_memory,double_precision=double_precision,$
            gaussian_source_models=gaussian_source_models, gaussian_x=gaussian_x, gaussian_y=gaussian_y, $
            gaussian_rot=gaussian_rot)
        FOR pol_i=0,n_pol-1 DO (*model_uv_full[pol_i])[uv_i_use]+=*model_uv_vals[pol_i]
        undefine_fhd,model_uv_vals,flux_arr
    ENDELSE
ENDELSE

END
