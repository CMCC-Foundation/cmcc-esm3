#! /bin/bash 
#
# Long term archive script for CMCC cluster 
# Designed for CMIP7 STANDARD output of 1x1 degree ocn/atm model
#
set -x
#
#module list

# DEFINE HERE THE FREQUENCY OF CLEAN UP
#CLEANFREQ=200

# DEFINE HERE THE FREQUENCY OF RESTART ARCHIVING 
RSTARFREQ=10

# DEFLATE LEVEL FOR NCCOPY CONVERSION TO NC4 FORMAT
DEFLEV=4

# FORCE PROCESSING YEAR (SET YEAR AND MANUALLY RUN case.lt_archive)
#USEYEAR=""

#############################################################
#  Functions

cat_clean() {
   # merge data and remove inputfiles. Check if merged file equals expected one (totrec)
   dwork=${1} ; trgfile=${2} ; inpfile=${3} ; totrec=${4}
   #
   thefiles=`ls ${dwork}/${inpfile} 2> /dev/null`
   if [ "x${thefiles}" != "x" ] ; then
      ncrcat -h -O ${thefiles} ${dwork}/${trgfile}
      trec=`ncdump -h ${dwork}/${trgfile} | grep "UNLIMITED" | grep -o -P '(?<=\().*(?= )'`
      if [ "${trec}" == ${totrec} ] ; then
         rm -rf ${thefiles}
      else
         echo "Bad number of timesteps in merged file $trgfiles" ; exit 1
      fi
   fi
}

cat_compr() {
   # merge data and compress inputfiles (no clean). Check if merged file equals expected one (totrec)
   dwork=${1} ; trgfile=${2} ; inpfile=${3} ; totrec=${4}
   #
   thefiles=`ls ${dwork}/${inpfile} 2> /dev/null`
   if [ "x${thefiles}" != "x" ] ; then
      ncrcat -h -O ${thefiles} ${dwork}/${trgfile}
      # check timesteps in merged file (12 months, 365 days)
      trec=`ncdump -h ${dwork}/${trgfile} | grep "UNLIMITED" | grep -o -P '(?<=\().*(?= )'`
      if [ "${trec}" == ${totrec} ] ; then
         # rewrite data to NC4 compressed
         for iff in ${thefiles} ; do
            dimunlim=`ncdump -h ${iff} | grep UNLIMITED | cut -d '=' -f1 | tr -d ' '` 
            mv ${iff} ${iff}_tmp
            nccopy -k 3 -d ${DEFLEV} -c ${dimunlim}/1 ${iff}_tmp ${iff}
            rm  ${iff}_tmp
         done
      else
         echo "Bad number of timesteps in merged file $trgfiles" ; exit 1
      fi
   fi
}

compr() {
   # Only compress inputfiles in st_archive
   dwork=${1} ; inpfile=${2}
   #
   thefiles=`ls ${dwork}/${inpfile} 2> /dev/null`
   if [ "x${thefiles}" != "x" ] ; then
      # rewrite data to NC4 compressed
      for iff in ${thefiles} ; do
         dimunlim=`ncdump -h ${iff} | grep UNLIMITED | cut -d '=' -f1 | tr -d ' '`
         mv ${iff} ${iff}_tmp
         nccopy -k 3 -d ${DEFLEV} -c ${dimunlim}/1 ${iff}_tmp ${iff}
         rm  ${iff}_tmp
      done
   fi
}

mv_arch () {
   # copy input files to archive and remove
   dhome=${1} ; darch=${2} ; inpfile=${3}
   here=`pwd` ; cd $dhome
   thefiles=`eval "ls ${inpfile}"`
   cp ${thefiles} ${darch}
   rm ${thefiles}
   cd ${here}
}

tar_arch () {
   # create a tarball to be archived and remove input files
   dhome=${1} ; darch=${2} ; outfile=${3} ; inpfile=${4}
   here=`pwd` ; cd $dhome
   thefiles=`eval "ls ${inpfile}"`
   tar -cf ${outfile} ${thefiles}
   mv ${dhome}/${outfile} ${darch}/${outfile}
   rm ${thefiles}
   cd ${here}
}

rst_arch () {
   dhome=${1} ; darch=${2} ; rstdir=${3} ; dcase=${4}
   here=`pwd` ; cd $dhome
   thistar="${dcase}.${rstdir}.tar"
   tar -zcf ${thistar} ${rstdir}
   mv ${dhome}/${thistar} ${darch}/${thistar}
   cd ${here}
}

#############################################################
#  Begin Execution
echo "Begin `basename "$0"`"
echo `pwd`

# Main Job info
caseid=${CASE} && echo "caseid : ${caseid} (CASEROOT is ${CASEROOT})"
jobid=${LSB_JOBID} && echo "jobid : ${jobid}"
st_archive_dir=${DOUT_S_ROOT} && echo "st_archive ${st_archive_dir}"
lt_archive_dir=${DOUT_L_ROOT} && echo "lt_archive ${lt_archive_dir}"

#############################################################
echo "This script is designed for the output of 1x1 degree ocn/atm model" 

if [[ ! ${STOP_OPTION} =~  "nyears" ]] ; then echo "This script is designed only for yearly resubmission." ; exit 0 ; fi

#############################################################
# PREAMBLE

# Create Long Term Archive folder
allcmp="atm ice lnd ocn rof rest"
for cc in ${allcmp} ; do
   if [ ! -d ${lt_archive_dir}/${cc} ] ; then mkdir -p ${lt_archive_dir}/${cc} ; fi
done

# Create temporary folder in short-term archive
if [ ! -d ${st_archive_dir}/tmp ] ; then
   mkdir -p ${st_archive_dir}/tmp
fi

# Get start and currently executed year
iniyear=`echo ${RUN_STARTDATE} | head -c 4`
curyear=`echo ${RUN_CURDATE} | head -c 4`

# User forced year
if [ "x${USEYEAR}" != "x" ] ; then
   curyear=${USEYEAR}
fi

# Next and Previous years
nexyear=`printf "%04d" $(expr ${curyear} + 1)`
preyear=`printf "%04d" $(expr ${curyear} - 1)`

# check that next year restart folder exists, if not something went wrong !
if [ "x${USEYEAR}" == "x" ] ; then
   nexrst=`ls -d ${st_archive_dir}/rest/${nexyear}*`
   if [ "x$nexrst" == "x" ] ; then
      echo "ERROR : Restart folder of next year ${nexyear} is missing... Something went wrong!"
      echo "        Check for missing archive execution and re-process manually (USEYEAR)"
      exit 12
   fi
fi

#############################################################
# 0. ORGANIZE DATA PACKING FOR EACH COMPONENT 
#    Configure this section according to model setup
#
#    All data packed are packed (or renamed) per year    

HERE=`pwd`

#   -----  CAM5  -----
#
cmp="atm" ; model="cam"
htapes="0a 0i"
for htape in ${htapes} ; do
   outfile="${caseid}.${model}.h${htape}.${curyear}.nc"
   inpfile="${caseid}.${model}.h${htape}.${curyear}-[0-9][0-9].nc"
   cat_clean ${st_archive_dir}/${cmp}/hist ${outfile} ${inpfile} 12
done

#htapes="1 2"
#for htape in ${htapes} ; do
#   outfile="${caseid}.${model}.h${htape}.${curyear}.nc"
#   inpfile="${caseid}.${model}.h${htape}.${curyear}-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9][0-9].nc"
#   mv ${st_archive_dir}/${cmp}/hist/${inpfile} ${st_archive_dir}/${cmp}/hist/${outfile}
#done

#   -----  CICE  -----
#
cmp="ice" ; model="cice"
# rename cice h file to h0 to harmonize with other CESM tapes
outfile="${caseid}.${model}.h0.${curyear}.nc"
inpfile="${caseid}.${model}.h.${curyear}-[0-9][0-9].nc"
cat_clean ${st_archive_dir}/${cmp}/hist ${outfile} ${inpfile} 12

#htape="1"
#outfile="${caseid}.${model}.h${htape}.${curyear}.nc"
#inpfile="${caseid}.${model}.h${htape}.${curyear}-[0-9][0-9]-[0-9][0-9].nc"
#cat_clean ${st_archive_dir}/${cmp}/hist ${outfile} ${inpfile} 365

#   -----  CLM45  -----
#
cmp="lnd" ; model="clm2"
htapes="0"
for htape in ${htapes} ; do
   outfile="${caseid}.${model}.h${htape}.${curyear}.nc"
   inpfile="${caseid}.${model}.h${htape}.${curyear}-[0-9][0-9].nc"
   cat_clean ${st_archive_dir}/${cmp}/hist ${outfile} ${inpfile} 12
done

#htapes="1"
#for htape in ${htapes} ; do
#   outfile="${caseid}.${model}.h${htape}.${curyear}.nc"
#   inpfile="${caseid}.${model}.h${htape}.${curyear}-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9][0-9].nc"
#   mv ${st_archive_dir}/${cmp}/hist/${inpfile} ${st_archive_dir}/${cmp}/hist/${outfile}
#done

#htapes="2" # Yealy mean files are created with the nexyear name
#for htape in ${htapes} ; do
#   outfile="${caseid}.${model}.h${htape}.${curyear}.nc"
#   inpfile="${caseid}.${model}.h${htape}.${nexyear}-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9][0-9].nc"
#   mv ${st_archive_dir}/${cmp}/hist/${inpfile} ${st_archive_dir}/${cmp}/hist/${outfile}
#done

#   -----  RTM  -----
#
cmp="rof" ; model="hydros"
htape=0
outfile="${caseid}.${model}.h${htape}.${curyear}.nc"
inpfile="${caseid}.${model}.h${htape}.${curyear}-[0-9][0-9].nc"
cat_clean ${st_archive_dir}/${cmp}/hist ${outfile} ${inpfile} 12

#htape=1 ; nsteps=365
#if [ ${curyear} == ${iniyear} ] && [ "${RUN_TYPE}" != "branch" ] ; then nsteps=364 ; fi # this is a fix for missing first day in hybrid/startup mode
#outfile="${caseid}.${model}.h${htape}.${curyear}.nc"
#inpfile="${caseid}.${model}.h${htape}.${curyear}-[0-9][0-9]-[0-9][0-9].nc"
#cat_clean ${st_archive_dir}/${cmp}/hist ${outfile} ${inpfile} ${nsteps}

#############################################################
# 1 CONVERT ALL OUTPUTS TO NETCDF4 COMPRESSED FORMAT
#   This operation streamline the archiving operations
#   nccopy is preferable to safely operate NC4 deflate
#

allcmp="atm ice lnd rof ocn"

for ccc in ${allcmp} ; do
    if [ "$ccc" != "ocn" ] ; then
       thefiles=`ls ${st_archive_dir}/${ccc}/hist/${caseid}.*.h[0-9]*.${curyear}.nc`
    else
       thefiles=`ls ${st_archive_dir}/${ccc}/hist/${caseid}_*_${curyear}*_${curyear}*_*.nc`
    fi
    if [ "x${thefiles}" != "x" ] ; then
       cmpfiles=${thefiles}
       for ff in ${thefiles} ; do  
          iscomp=`ncdump -s -h ${ff} | grep "_DeflateLevel" | tail -1` 
          dunlim=`ncdump -h ${ff} | grep UNLIMITED | cut -d '=' -f1 | tr -d ' '`
          if [ "x${iscomp}" == "x" ] ; then
             nccopy -k 3 -d ${DEFLEV} -c ${dunlim}/1 ${ff} ${ff}.4 &
          else 
             cmpfiles=`echo $cmpfiles | sed -e "s@${ff}@@"` 
          fi
       done
       wait
       if [ "x${cmpfiles}" != "x" ] ; then
          for ff in ${cmpfiles} ; do mv ${ff}.4 ${ff} ; done
       fi
    fi
done

#############################################################
# 2 CREATE TARBALL ARCHIVES OF OUTPUT DATA
#
# TAR NOT DONE IN THIS VERSION (TAR version at commit 4c0eee4f)

# Directly move NetCDF-ZIP data to Archive folder

#### OCN likely to remove
####cmp="ocn" ; model="nemo"
#### Keep grid_T, scalar, and grid_ptr for quick_diag
####cp ${st_archive_dir}/${cmp}/hist/${caseid}_1m_${curyear}*_${curyear}*_grid_T.nc   ${st_archive_dir}/${cmp}/hist/${caseid}_1m_${curyear}0101_grid_T.nc
####cp ${st_archive_dir}/${cmp}/hist/${caseid}_1m_${curyear}*_${curyear}*_grid_ptr.nc ${st_archive_dir}/${cmp}/hist/${caseid}_1m_${curyear}0101_grid_ptr.nc
####cp ${st_archive_dir}/${cmp}/hist/${caseid}_1m_${curyear}*_${curyear}*_scalar.nc   ${st_archive_dir}/${cmp}/hist/${caseid}_1m_${curyear}0101_scalar.nc

# Move data to Archive folder
allcmp="atm ice lnd rof ocn"

for cmp in ${allcmp} ; do
   if [ "$cmp" != "ocn" ] ; then
      thefiles="${caseid}.*.h[0-9]*.${curyear}.nc"
   else
      thefiles="${caseid}_*_${curyear}*_${curyear}*_*.nc"
   fi
   mv_arch ${st_archive_dir}/${cmp}/hist ${lt_archive_dir}/${cmp} ${thefiles} &
done

wait

############################################################# TO CHECK
## 3 CLEAN UP HISTORY in the ST_ARCHIVE
if [ "x${USEYEAR}" == "x" ] ; then
    #   -----  CAM  -----
    #
    cmp="atm" ; model="cam"
    remove_file=`ls ${st_archive_dir}/${cmp}/hist/${caseid}.${model}.i.${nexyear}-*.nc`
    if [ "x${remove_file}" != "x" ] ; then
       rm ${remove_file}
    fi
    if [ -f ${remove_file} ] ; then
       rm ${remove_file}
    fi
fi

#############################################################
# 4 REMOVE PREVIOUS RESTART AND COPY TO ARCHIVE EVERY RSTARFREQ
lstrst=`ls -d ${st_archive_dir}/rest/${nexyear}-[0-9][0-9]-[0-9][0-9]-00000 2> /dev/null `	    
lstrstn=`ls ${lstrst}/* | wc -l`
currst=`ls -d ${st_archive_dir}/rest/${curyear}-[0-9][0-9]-[0-9][0-9]-00000 2> /dev/null `		      
currstn=`ls ${currst}/* | wc -l`

if [ "x${lstrst}" == "x" ] ; then
   echo "Missing latest restart folder ${lstrst}"
   echo "EXIT lt_archive execution."
   exit 1
fi

if [ "${lstrstn}" != "${currstn}" ] && [ ${curyear} != ${iniyear} ] ; then
   echo "Latest restart folder has different number of files from the previous one"
   echo "LATEST : ${lstrst}" 
   echo "PREVIOUS : ${currst}"
   echo "EXIT lt_archive execution."
   exit 1
fi

remain=`expr ${curyear} % ${RSTARFREQ}` || remain=0

if [ "x${currst}" != "x" ] ; then
   # archive this restart if multiple of ${RSTARFREQ}
   if [ ${remain} -eq 0 ] ; then
      thisrest=`echo "${currst}" | rev | cut -d '/' -f1 | rev`
      tmpdir=${st_archive_dir}/tmp/job.$jobid ; mkdir -p ${tmpdir}
      mv ${st_archive_dir}/rest/${thisrest} ${tmpdir}
      rst_arch ${tmpdir} ${lt_archive_dir}/rest ${thisrest} ${caseid}
      rm -rf ${tmpdir}
   else
      # remove restart folder
      rm -rf ${currst}
   fi
fi

############################################################# TO BE REMOVED
## 5 CLEAN UP ARCHIVED DATA TO CLEANFREQ FROM EXPERIMENT BEGIN DATE
#cmp=("atm" "ice" "lnd" "ocn" "rof") ; ncmps=`expr ${#cmp[@]} - 1`
#model=("cam" "cice" "clm2" "nemo" "rtm")
#
#simyears=`expr ${curyear} - ${iniyear}`
#remain=`expr ${simyears} % ${CLEANFREQ}` || remain=0
#
#if [ ${remain} -eq 0 ] && [ ${curyear} != ${iniyear} ] ; then
#   ybeg=`expr ${curyear} - ${CLEANFREQ}`
#   yend=`expr ${curyear} - 1`
#
#   echo "Clean up data on st_archive for the period ${ybeg}-${yend}."
#
#   for ii in `seq 0 1 ${ncmps}` ; do
#      if [ "${cmp[$ii]}" != "ocn" ] ; then
#         cleanfiles=`eval "ls ${st_archive_dir}/${cmp[$ii]}/hist/${caseid}.${model[$ii]}.h*.{${ybeg}..${yend}}*.nc" `
#      else
#         cleanfiles=`eval "ls ${st_archive_dir}/${cmp[$ii]}/hist/${caseid}_*_{${ybeg}..${yend}}[0-9][0-9][0-9][0-9]_*_*.nc"`
#      fi
#      rm ${cleanfiles}
#   done
#
#fi

echo "Done lt_archive for year ${curyear}" 
