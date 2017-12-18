#/bin/sh

LANG=C

for dir in $*
do
    echo $dir

    OF=${dir##*/}
    version=${dir##*/OpenFOAM-}

    origOF=$dir/../orig/${OF}
    if [ ! -d  "$origOF" ];then
	echo "Error: $origOF does not exist."
	exit 1
    fi
    patch=patches/OpenFOAM/${OF}
    (cd ${dir}
	diff -urN ../orig/$OF ./ \
--exclude=*~ \
--exclude=log* \
--exclude=*.rej \
--exclude=*.old \
--exclude=*.orig \
--exclude=applications \
--exclude=bin \
--exclude=doc \
--exclude=platforms \
--exclude=src \
--exclude=tutorials \
--exclude=DONE_* \
--exclude=PATCHED_DURING_OPENFOAM_BUILD \
--exclude=linux64*_* \
--exclude=00-ERRATA.txt \
) \
| grep -v "^diff" \
| awk '/^[+-][+-][+-]/ { printf "%s %s\t1970-01-01 00:00:00.000000000 +0000\n",$1,$2;next} {print $0}' \
> ${patch}
    [ -s ${patch} ] || rm -f ${patch}

    origTP=$dir/../orig/ThirdParty-${version}
    if [ ! -d $origTP ];then
	echo "Error: $origTP does not exist."
	exit 1
    fi

    patch=patches/OpenFOAM/ThirdParty-${version}
    (cd ${dir}/../ThirdParty-${version}
	diff -urN ../orig/ThirdParty-${version} ./ \
--exclude=platforms \
--exclude=build \
--exclude=CGAL-* \
--exclude=boost_* \
--exclude=cmake-* \
--exclude=fftw-* \
--exclude=gcc-* \
--exclude=gmp-* \
--exclude=mpc-* \
--exclude=mpfr-* \
--exclude=scotch-* \
--exclude=scotch_* \
--exclude=qt-* \
--exclude=Python-* \
--exclude=mesa-* \
--exclude=ParaView-* \
--exclude=openmpi-* \
--exclude=log.* \
--exclude=*~ \
--exclude=*.rej \
--exclude=*.orig \
--exclude=*.old \
--exclude=*.tmp \
--exclude=DONE_* \
--exclude=PATCHED_DURING_OPENFOAM_BUILD \
$option
) \
| grep -v "^diff" \
| awk '/^[+-][+-][+-]/ { printf "%s %s\t1970-01-01 00:00:00.000000000 +0000\n",$1,$2;next} {print $0}' \
 > ${patch}
[ -s ${patch} ] || rm -f ${patch}
done
