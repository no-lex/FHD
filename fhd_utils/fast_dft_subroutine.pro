FUNCTION fast_dft_subroutine,x_vec,y_vec,amp_vec,kernel_threshold=kernel_threshold,$
    dimension=dimension,elements=elements,resolution=resolution

IF N_Elements(elements) EQ 0 THEN elements=dimension
IF N_Elements(resolution) EQ 0 THEN resolution=100. ELSE resolution=Float(resolution)
IF N_Elements(kernel_threshold) EQ 0 THEN kernel_threshold=0.001

xv_test=Abs(meshgrid(dimension,elements,1)-dimension/2.)
yv_test=Abs(meshgrid(dimension,elements,2)-elements/2.)

kernel_test=1./(((!Pi*xv_test)>1.)*((!Pi*yv_test)>1.)) 
kernel_i=where(kernel_test GE kernel_threshold,n_k)

xv_k=(kernel_i mod dimension)-dimension/2.
yv_k=Floor(kernel_i/dimension)-elements/2.

kernel_arr=Ptrarr(resolution,resolution)
kernel_norm=0.
FOR i=0.,resolution-1 DO BEGIN
    IF i EQ 0 THEN BEGIN
        kernel_x=Sin(!DPi*(xv_k+i/resolution))/((!DPi*(xv_k+i/resolution))>1.)
        kernel_x[where(xv_k EQ 0)]=1.
    ENDIF ELSE kernel_x=Sin(!DPi*(xv_k+i/resolution))/(!DPi*(xv_k+i/resolution))
    FOR j=0.,resolution-1 DO BEGIN
        IF j EQ 0 THEN BEGIN
            kernel_y=Sin(!DPi*(yv_k+j/resolution))/((!DPi*(yv_k+j/resolution))>1.)
            kernel_y[where(yv_k EQ 0)]=1.
        ENDIF ELSE kernel_y=Sin(!DPi*(yv_k+j/resolution))/(!DPi*(yv_k+j/resolution))
        kernel_single=kernel_x*kernel_y
        kernel_norm+=Total(kernel_single)
        kernel_arr[i,j]=Ptr_new(Float(kernel_single))
    ENDFOR
ENDFOR
kernel_norm/=resolution^2.
FOR i=0.,resolution-1 DO FOR j=0.,resolution-1 DO *kernel_arr[i,j]*=kernel_norm 

x_offset=Round((Ceil(x_vec)-x_vec)*resolution) mod resolution    
y_offset=Round((Ceil(y_vec)-y_vec)*resolution) mod resolution
xcen0=Round(x_vec+x_offset/resolution) ;do this after offset, in case it has rounded to the next grid point
ycen0=Round(y_vec+y_offset/resolution)

si1=where((xcen0 GE 0) AND (ycen0 GE 0) AND (xcen0 LE dimension-1) AND (ycen0 LE elements-1),ns)

;test if any gridding kernels would extend beyond image boudaries
xv_test=Minmax(xcen0[si1])+Minmax(xv_k)
yv_test=Minmax(ycen0[si1])+Minmax(yv_k)

IF xv_test[0] LT 0 OR xv_test[1] GT dimension-1 OR yv_test[0] LT 0 OR yv_test[1] GT elements-1 THEN BEGIN
    mod_flag=1
    dimension_use=xv_test[1]-xv_test[0]
    elements_use=yv_test[1]-yv_test[0]
    xcen0-=xv_test[0]
    ycen0-=yv_test[0]
ENDIF ELSE BEGIN
    mod_flag=0 
    dimension_use=dimension
    elements_use=elements
ENDELSE

model_img_use=fltarr(dimension_use,elements_use)
FOR si=0L,ns-1L DO BEGIN
    model_img_use[xcen0[si1[si]]+xv_k,ycen0[si1[si]]+yv_k]+=amp_vec[si1[si]]*(*kernel_arr[x_offset[si1[si]],y_offset[si1[si]]])
    
ENDFOR
IF Keyword_Set(mod_flag) THEN BEGIN
    model_img=Fltarr(dimension,elements)
;    model_img[xv_test[0]>0:xv_test[1]<(dimension-1),yv_test[0]>0:yv_test[1]<(elements-1)]=model_img_use[Abs(xv_test[0]<0):
ENDIF ELSE model_img=model_img_use
Ptr_free,kernel_arr

RETURN,model_img
END