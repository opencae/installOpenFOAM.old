#!/bin/bash

#
# Usage
#
usage()
{
    while [ "$#" -ge 1 ]; do echo "$1"; shift; done
    echo
    cat<<USAGE
usage: ${0##*/} [OPTION]

options:
  -h|-help      help
  -gcc          PATH              Path to third party gcc
  -gmp          PATH              Path to third party gmp
  -mpfr         PATH              Path to third party mpfr
  -mpc          PATH              Path to third party mpc
  -boost        PATH              Path to third party boost
  -cgal         PATH              Path to third party CGAL
  -cmake        PATH              Path to third party cmkae
  -qt           PATH              Path to third party qt
  -python       PATH              Path to third party Python
  -mesa         PATH              Path to third party Mesa
  -paraview     PATH              Path to third party ParaView
  -openmpi      PATH              Path to third party OpenMPI
USAGE
    exit 1
}

#
# Write error message and exit
#
error()
{
    echo "Error: $1"
    exit 1
}

#
# Download file $1 from url $2 into download/ directory
#
downloadFile()
{
    [ "$#" -eq 2 ] || {
        echo "downloadFile called with incorrect number of arguments $@"
        return 1
    }

    local file="$1"
    local url="$2"

    [ -d download ] || mkdir download

    if [ ! -e download/$file ]
    then
        echo "downloading $file from $url"
	(
	    trap 'rm -f $file;error "Unable to download $file from $url"' 1 2 3 15
	    cd download && wget --no-check-certificate "$url" -O "$file"
	)
    fi
}

download_and_extract_source()
{
    for DIRECTORY in OpenFOAM ThirdParty
    do
	local PACKAGE=$DIRECTORY-$FOAM_VERSION
	if [ ! -d $FOAM_INST_DIR/$PACKAGE ];then
	    local source_file=$PACKAGE.tgz
	    if [ $DIRECTORY = "OpenFOAM" ];then
		local URL="$(openfoam_url $PACKAGE)"
	    else
		local URL="$(thirdparty_url $PACKAGE)"
	    fi
	    downloadFile "$source_file" "$URL"
	
	    tar xpf download/$source_file -C $FOAM_INST_DIR
	    local REPOSITORY_VERSION=${FOAM_VERSION%.*}.x
	    if [ -d $FOAM_INST_DIR/$DIRECTORY-$REPOSITORY_VERSION-version-$FOAM_VERSION ];then
		mv $FOAM_INST_DIR/$DIRECTORY-$REPOSITORY_VERSION-version-$FOAM_VERSION \
		    $FOAM_INST_DIR/$PACKAGE
	    fi
	else
	    echo "$PACKAGE is already extracted in $FOAM_INST_DIR"
	fi
    done
}

patch_source()
{
    [ -n "$DOWNLOAD_ONLY" ] && return 0

    for DIRECTORY in OpenFOAM ThirdParty
    do
	local PACKAGE=$DIRECTORY-$FOAM_VERSION
	local patchFile="$PWD/patches/OpenFOAM/$DIRECTORY-$FOAM_VERSION"
	if [ -f $patchFile ];then
	    (
		cd $FOAM_INST_DIR/$PACKAGE
		local sentinel="PATCHED_DURING_OPENFOAM_BUILD"
		if [ -f "$sentinel" ]
		then
		    echo "patch for $PACKAGE was already applied"
		else
		    echo "apply patch $patchFile for $PACKAGE"
		    touch "$sentinel"
		    sed \
	-e s/"^\(+boost_version=\).*"/"\1"\"$BOOST_PACKAGE\"/ \
	-e s/"^\(+cgal_version=\).*"/"\1"\"$CGAL_PACKAGE\"/ \
	-e s/"^\(+cmakePACKAGE=\).*"/"\1"\"$CMAKE_PACKAGE\"/ \
	-e s/"^\(+fftw_version=\).*"/"\1"\"$FFTW_PACKAGE\"/ \
	-e "s/^\(+gccPACKAGE=\).*"/"\1"\"$GCC_PACKAGE\"/ \
	-e "s/^\(+gmpPACKAGE=\).*"/"\1"\"$GMP_PACKAGE\"/ \
	-e "s/^\(+mpcPACKAGE=\).*"/"\1"\"$MPC_PACKAGE\"/ \
	-e "s/^\(+mpfrPACKAGE=\).*"/"\1"\"$MPFR_PACKAGE\"/ \
	-e s/"^\(+qtVERSION=\).*"/"\1"\"${QT_PACKAGE#qt-}\"/ \
			$patchFile | \
			patch -b -l -p1 2>&1 | tee $sentinel
		fi
	    )
	fi
    done

    for patchFile in $PWD/patches/ThirdParty/*
    do
	local PACKAGE=${patchFile##*/}
	[ ${PACKAGE%-*} = "paraview" ] && PACKAGE="${PACKAGE/paraview/ParaView}"
	local dir=$FOAM_INST_DIR/ThirdParty-$FOAM_VERSION/$PACKAGE
	echo $dir
	if [ -d $dir ];then
	    (
		cd $dir
		local sentinel="PATCHED_DURING_OPENFOAM_BUILD"
		if [ -f "$sentinel" ]
		then
		    echo "patch for $PACKAGE was already applied"
		else
		    echo "apply patch $patchFile for $PACKAGE"
		    touch "$sentinel"
		    patch -b -l -p1 < $patchFile 2>&1 | tee $sentinel
		fi
	    )
	fi
    done
}

link_ThirdParty_package()
{
    local PACKAGE=$1
    local ARCH=$2
    local PATH_TO_THIRDPARTY_PACKAGE=$3

    if [ $PATH_TO_THIRDPARTY_PACKAGE = "auto" ];then
	for LINK_VERSION in \
2.3.0 \
2.3.1 \
2.4.0 \
3.0.0 \
3.0.1 \
v3.0+ \
4.0 \
4.1 \
v1606+ \
v1612+ \

	do
	    local LINK_PATH=$FOAM_INST_DIR/ThirdParty-$LINK_VERSION/platforms/$ARCH/$PACKAGE
	    if [ -d $FOAM_INST_DIR/ThirdParty-$LINK_VERSION/platforms/$ARCH/$PACKAGE ];then
		PATH_TO_THIRDPARTY_PACKAGE=$LINK_PATH
		break
	    fi
	done

	if [ $PATH_TO_THIRDPARTY_PACKAGE = "auto" ];then
	    echo "Warning: $PACKAGE does not exist in any other version."
	    return 0
	fi
    fi

    [ -d $WM_THIRD_PARTY_DIR/platforms/$ARCH ] || \
	mkdir -p $WM_THIRD_PARTY_DIR/platforms/$ARCH
    rm -rf $WM_THIRD_PARTY_DIR/platforms/$ARCH/$PACKAGE
    ln -s $PATH_TO_THIRDPARTY_PACKAGE \
	$WM_THIRD_PARTY_DIR/platforms/$ARCH/$PACKAGE

    echo "Link $WM_THIRD_PARTY_DIR/platforms/$ARCH/$PACKAGE to $PATH_TO_THIRDPARTY_PACKAGE"

    return 0
}

download_and_extract_package()
{
    local PACKAGE="$1"
    local URL="$2"

    local PACKAGE_FILE="${URL##*/}"
    PACKAGE_FILE="${PACKAGE_FILE%\?*}"

    [ "${PACKAGE%%-*}" = "qt" ] && PACKAGE="qt-everywhere-opensource-src-${PACKAGE#*-}"

    if [ ! -d $WM_THIRD_PARTY_DIR/$PACKAGE ];then
	local source_file=$PACKAGE_FILE
	downloadFile $source_file "$URL"
	tar xpf download/$source_file -C $WM_THIRD_PARTY_DIR
    fi
}

link_or_download()
{
    local PACKAGE=$1
    local ARCH=$2
    local URL="$3"
    local PATH_TO_THIRDPARTY=$4

    if [ -n "$PATH_TO_THIRDPARTY" ];then
	link_ThirdParty_package "$PACKAGE" "$ARCH" "$PATH_TO_THIRDPARTY"
    fi

    local ARCH_PATH=$WM_THIRD_PARTY_DIR/platforms/$ARCH/$PACKAGE
    if [ ! -d $ARCH_PATH ];then
	download_and_extract_package "$PACKAGE" "$URL"
    fi
}

link_to_another_compiler()
{
    local COMPILER=$1
    local PACKAGE=$2

    [ $COMPILER_NAME != "Icc" ] && return 1

    GCC_COMPATIBILITY_VERSION=`icc -v  2>&1 |cut -d ' ' -f 6 | tr '.' '_'`

    dir=$WM_THIRD_PARTY_DIR/platforms/${WM_ARCH}Gcc${GCC_COMPATIBILITY_VERSION}

    if expr $COMPILER : "KNL$" > /dev/null; then
	dir=${dir}KNL
    fi

    if [ -d $dir/$PACKAGE ];then
	[ -d $WM_THIRD_PARTY_DIR/platforms/${WM_ARCH}${COMPILER} ] || \
	    mkdir -p $WM_THIRD_PARTY_DIR/platforms/${WM_ARCH}${COMPILER}
	ln -s $dir/$PACKAGE $WM_THIRD_PARTY_DIR/platforms/${WM_ARCH}${COMPILER}/$PACKAGE

	echo "Link to $WM_THIRD_PARTY_DIR/platforms/${WM_ARCH}${COMPILER}/$PACKAGE"

	return 0
    fi

    return 1
}

download_CGAL()
{
    [ "$CGAL_PACKAGE" = "cgal-none" ] && return 0

    local PACKAGE=$CGAL_PACKAGE

    local ARCH_PATH=$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/$PACKAGE
    if [ ! -d $ARCH_PATH  ];then
	link_to_another_compiler $WM_COMPILER $PACKAGE || \
	    link_or_download "$PACKAGE" "$WM_ARCH$WM_COMPILER" \
	    "$(cgal_url $PACKAGE)" "$PATH_TO_THIRDPARTY_CGAL"
    else
	echo "$PACKAGE is already installed in $ARCH_PATH"
    fi
}

download_Boost()
{
    [ "$BOOST_PACKAGE" = "boost-none" ] && return 0

    local PACKAGE=$BOOST_PACKAGE

    local ARCH_PATH=$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/$PACKAGE
    if [ ! -d $ARCH_PATH  ];then
	link_to_another_compiler $WM_COMPILER $PACKAGE || \
	    link_or_download "$PACKAGE" "$WM_ARCH$WM_COMPILER" \
	    "$(boost_url $PACKAGE)" "$PATH_TO_THIRDPARTY_BOOST"
    else
	echo "$PACKAGE is already installed in $ARCH_PATH"
    fi
}

build_Gcc()
{
    . $WM_PROJECT_DIR/etc/bashrc \
	foamCompiler=system WM_COMPILER_TYPE=system WM_COMPILER=Gcc WM_MPLIB=dummy
	
    [ -d  $WM_THIRD_PARTY_DIR/platforms ] \
	|| mkdir  $WM_THIRD_PARTY_DIR/platforms

    local GMP_ARCH_PATH=$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH/$GMP_PACKAGE
    if [ ! -d $GMP_ARCH_PATH  ];then
	local GMP_PACKAGE=${GMP_ARCH_PATH##*/}
	local URL="$(gmp_url $GMP_PACKAGE)"
	link_or_download $GMP_PACKAGE "$WM_ARCH" "$URL" $PATH_TO_THIRDPARTY_GMP
    else
	echo "$GMP_PACKAGE package is already installed in $GMP_ARCH_PATH"
    fi

    if [ -d $GMP_ARCH_PATH/lib -a ! -d $GMP_ARCH_PATH/lib64 ];then
	(cd $GMP_ARCH_PATH;rm -f lib64;ln -s lib lib64)
    fi
    if [ -d $GMP_ARCH_PATH/lib64 -a ! -d $GMP_ARCH_PATH/lib ];then
	(cd $GMP_ARCH_PATH;rm -f lib;ln -s lib64 lib)
    fi

    local MPFR_ARCH_PATH=$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH/$MPFR_PACKAGE
    if [ ! -d $MPFR_ARCH_PATH  ];then
	local MPFR_PACKAGE=${MPFR_ARCH_PATH##*/}
	local URL="$(mpfr_url $MPFR_PACKAGE)"
	link_or_download $MPFR_PACKAGE "$WM_ARCH" "$URL" $PATH_TO_THIRDPARTY_MPFR
    else
	echo "$MPFR_PACKAGE package is already installed in $MPFR_ARCH_PATH"
    fi

    if [ -d $MPFR_ARCH_PATH/lib -a ! -d $MPFR_ARCH_PATH/lib64 ];then
	(cd $MPFR_ARCH_PATH;rm -f lib64;ln -s lib lib64)
    fi
    if [ -d $MPFR_ARCH_PATH/lib64 -a ! -d $MPFR_ARCH_PATH/lib ];then
	(cd $MPFR_ARCH_PATH;rm -f lib;ln -s lib64 lib)
    fi

    local MPC_ARCH_PATH=$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH/$MPC_PACKAGE
    if [ ! -d $MPC_ARCH_PATH ];then
	local MPC_PACKAGE=${MPC_ARCH_PATH##*/}
	local URL="$(mpc_url $MPC_PACKAGE)"
	link_or_download $MPC_PACKAGE "$WM_ARCH" "$URL" $PATH_TO_THIRDPARTY_MPC
    else
	echo "$MPC_PACKAGE package is already installed in $MPC_ARCH_PATH"
    fi

    if [ -d $MPC_ARCH_PATH/lib -a ! -d $MPC_ARCH_PATH/lib64 ];then
	(cd $MPC_ARCH_PATH;rm -f lib64;ln -s lib lib64)
    fi
    if [ -d $MPC_ARCH_PATH/lib64 -a ! -d $MPC_ARCH_PATH/lib ];then
	(cd $MPC_ARCH_PATH;rm -f lib;ln -s lib64 lib)
    fi

    local GCC_ARCH_PATH=$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH/$GCC_PACKAGE
    if [ ! -d $GCC_ARCH_PATH -o ! -d $GMP_ARCH_PATH  -o ! -d $MPFR_ARCH_PATH -o ! -d $MPC_ARCH_PATH ];then
	if [ $COMPILER_NAME = "Gcc" -a  $COMPILER_TYPE != "system" ];then
	    local URL="$(gcc_url $GCC_PACKAGE)"
	    link_or_download $GCC_PACKAGE "$WM_ARCH" "$URL" $PATH_TO_THIRDPARTY_GCC
        fi

	[ -n "$DOWNLOAD_ONLY" ] && return 0

	    if [ $COMPILER_NAME != "Gcc" -o $COMPILER_TYPE = "system" ];then
	    # make dummy directory
	    [ ! -d $GCC_ARCH_PATH ] && mkdir -p $GCC_ARCH_PATH
	fi
	(cd $WM_THIRD_PARTY_DIR
	    . $WM_PROJECT_DIR/etc/bashrc $foam_settings \
		foamCompiler=system WM_COMPILER_TYPE=system WM_COMPILER=Gcc

	    # make dummy directory
	    [ ! -d ${GCC_ARCH_PATH##*/} ] && mkdir ${GCC_ARCH_PATH##*/}

	    chmod +x makeGcc
	    time bash -e ./makeGcc $GMP_PACKAGE $MPFR_PACKAGE $MPC_PACKAGE $GCC_PACKAGE

	    [ -z "$(ls -A ${GCC_ARCH_PATH##*/})" ] && rmdir ${GCC_ARCH_PATH##*/}
	)
	if [ $COMPILER_NAME != "Gcc" -o $COMPILER_TYPE = "system" ];then
	    [ -z "$(ls -A $GCC_ARCH_PATH/)" ] && rmdir $GCC_ARCH_PATH
	fi
    else
	echo "$GCC_PACKAGE package is already installed in $GCC_ARCH_PATH"
    fi
}

add_wmake_rules()
{
    [ -n "$DOWNLOAD_ONLY" ] && return 0

    local RULES=$WM_PROJECT_DIR/wmake/rules

    local DST_COMPILER=$RULES/$WM_ARCH$WM_COMPILER
    if [ ! -d $DST_COMPILER ];then
	local SRC_COMPILER=$RULES/$WM_ARCH$COMPILER_WM_NAME
	[ -d $SRC_COMPILER ] || error "wmake rule $SRC_COMPILER does not exist"
	cp -a $SRC_COMPILER $DST_COMPILER
    fi

    local DST_MPLIB_GENERAL=$RULES/General/mplib$WM_MPLIB
    local MPLIB_ORIG=`echo $WM_MPLIB | tr -d [:digit:]_`
    if [ ! -f $DST_MPLIB_GENERAL ];then
	local SRC_MPLIB_GENERAL=$RULES/General/mplib$MPLIB_ORIG
	if [ -f $SRC_MPLIB_GENERAL ];then
	    cp -a $SRC_MPLIB_GENERAL $DST_MPLIB_GENERAL
	fi
    fi

    local DST_MPLIB_COMPILER=$RULES/$WM_ARCH$WM_COMPILER/mplib$WM_MPLIB
    if [ ! -f $DST_MPLIB_COMPILER ];then
	local SRC_MPLIB_COMPILER=$RULES/$WM_ARCH$WM_COMPILER/mplib$MPLIB_ORIG
	if [ -f $SRC_MPLIB_COMPILER ];then
	    cp -a $SRC_MPLIB_COMPILER $DST_MPLIB_COMPILER
	fi
    fi
}

download_OpenMPI()
{
    if [ $MPLIB != "OPENMPI" ];then
	echo "Skip download_openmpi since MPLIB is not OPENMPI"
	return 0
    fi

    if [ ! -d $MPI_ARCH_PATH ];then
	local PACKAGE=${MPI_ARCH_PATH##*/}

	# Extract from OpenMPI tar ball if version is 2.4.0 since
        # OpenMPI source in ThirdParty-2.4.0 is incompelete.
	# See https://bugs.openfoam.orig/view.php?id=1770
	if [ $FOAM_VERSION = "2.4.0" ];then
	    if [ ! -d $WM_THIRD_PARTY_DIR/$PACKAGE.orig \
		-a -d $WM_THIRD_PARTY_DIR/$PACKAGE ];then
		mv $WM_THIRD_PARTY_DIR/$PACKAGE \
		    $WM_THIRD_PARTY_DIR/$PACKAGE.orig
	    fi
	fi

	link_or_download "$PACKAGE" "$WM_ARCH$WM_COMPILER" \
	    "$(openmpi_url $PACKAGE)" "$PATH_TO_THIRDPARTY_OPENMPI"
    else
	echo "OpenMPI package is already installed in $MPI_ARCH_PATH"
    fi
}

download_FFTW()
{
    [ $FFTW_PACKAGE = "fftw-none" ] && return 0
    [ $FFTW_PACKAGE = "fftw-system" ] && return 0

    if [ -n "$FFTW_ARCH_PATH" ];then
	if [ ! -d $FFTW_ARCH_PATH ];then
	    local PACKAGE=${FFTW_ARCH_PATH##*/}
	    local URL="$(fftw_url $PACKAGE)"
	    download_and_extract_package "$PACKAGE" "$URL"
	else
	    echo "$PACKAGE is already installed in $FFTW_ARCH_PATH"
	fi
    else
	echo "Skip downloading FFTW since FFTW_ARCH_PATH is not set"
    fi
}

build_CMake()
{
    local PACKAGE=$CMAKE_PACKAGE

    local ARCH_PATH=$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/$PACKAGE

    if [ ! -d $ARCH_PATH  ];then
	link_to_another_compiler $WM_COMPILER $PACKAGE  || \
	    link_or_download "$PACKAGE" "$WM_ARCH$WM_COMPILER" \
	    "$(cmake_url $PACKAGE)" "$PATH_TO_THIRDPARTY_CMAKE"

	[ -n "$DOWNLOAD_ONLY" ] && return 0

	if [ ! -d $ARCH_PATH  ];then
	    (cd $WM_THIRD_PARTY_DIR
		chmod +x makeCmake
		time ./makeCmake $PACKAGE
	    )
	fi
    else
	echo "$PACKAGE is already installed in $ARCH_PATH"
    fi

    export PATH=$ARCH_PATH/bin:$PATH
    which cmake
}

build_Mesa()
{
    [ -n "$BUILD_PARAVIEW" ] || return 0

    local PACKAGE=$MESA_PACKAGE

    local ARCH_PATH=$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/$PACKAGE
    if [ ! -d $ARCH_PATH  ];then
	link_to_another_compiler $WM_COMPILER $PACKAGE || \
	    link_or_download $PACKAGE "$WM_ARCH$WM_COMPILER" \
	    "$(mesa_url $PACKAGE)" "$PATH_TO_THIRDPARTY_MESA"

	[ -n "$DOWNLOAD_ONLY" ] && return 0

	if [ ! -d $ARCH_PATH  ];then
	    (cd $WM_THIRD_PARTY_DIR
		chmod +x makeMesa
		time ./makeMesa $MESA_PACKAGE
	    )
	fi
    else
	echo "$PACKAGE is already installed in $ARCH_PATH"
    fi

    if [ -d $ARCH_PATH/lib -a ! -d $ARCH_PATH/lib64 ];then
	(cd $ARCH_PATH;rm -f lib64;ln -s lib lib64)
    fi
}

build_Qt()
{
    [ -n "$BUILD_PARAVIEW" ] || return 0

    local PACKAGE=$QT_PACKAGE

    local ARCH_PATH=$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/$PACKAGE
    if [ ! -d $ARCH_PATH ];then
	link_to_another_compiler $WM_COMPILER $PACKAGE || \
	    link_or_download $PACKAGE "$WM_ARCH$WM_COMPILER" \
	    "$(qt_url $PACKAGE)" "$PATH_TO_THIRDPARTY_QT"

	[ -n "$DOWNLOAD_ONLY" ] && return 0

	if [ ! -d $ARCH_PATH ];then
	    (cd $WM_THIRD_PARTY_DIR
		. $WM_PROJECT_DIR/etc/bashrc $foam_settings
		chmod +x makeQt
		time ./makeQt
	    )
	fi
    else
	echo "$PACKAGE is already installed in $ARCH_PATH"
    fi
}

build_Python()
{
    [ -n "$BUILD_PARAVIEW" ] || return 0
    [ "$PYTHON_TYPE" = "system" ] && return 0

    PYTHON_VERSION=${PYTHON_PACKAGE#Python-}

    local PYTHON_MAJOR_VERSION=${PYTHON_VERSION%.*}
    local PACKAGE=$PYTHON_PACKAGE

    local ARCH_PATH=$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/$PACKAGE
    if [ ! -d $ARCH_PATH ];then
	link_to_another_compiler $WM_COMPILER $PACKAGE || \
	    link_or_download $PACKAGE "$WM_ARCH$WM_COMPILER" \
	    "$(python_url $PACKAGE)" "$PATH_TO_THIRDPARTY_PYTHON"

	[ -n "$DOWNLOAD_ONLY" ] && return 0

	if [ ! -d $ARCH_PATH ];then
	    (
		cd $WM_THIRD_PARTY_DIR/$PACKAGE
		./configure --prefix=$ARCH_PATH --enable-shared --enable-unicode=ucs4
		time make -j $WM_NCOMPPROCS && make altinstall
		(cd $WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/$PACKAGE/bin
		    ln -s python$PYTHON_MAJOR_VERSION python
		)
	    )
	fi
    else
	echo "$PACKAGE is already installed in $ARCH_PATH"
    fi
}

build_ParaView()
{
    [ -n "$BUILD_PARAVIEW" ] || return 0

    local PACKAGE=$PARAVIEW_PACKAGE
    local VERSION=${PARAVIEW_PACKAGE#ParaView-}
    local QMAKE_PATH=$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/$QT_PACKAGE/bin/qmake
    local PYTHON_VERSION=${PYTHON_PACKAGE#Python-}
    local PYTHON_MAJOR_VERSION=${PYTHON_VERSION%.*}

    local ARCH_PATH=$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/$PACKAGE
    local PYTHON_ARCH_PATH=$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/$PYTHON_PACKAGE
    if [ ! -d $ARCH_PATH ];then
	link_to_another_compiler $WM_COMPILER $PACKAGE
	if [ $? -eq 1 ];then
	    if [ -n "$PATH_TO_THIRDPARTY_PARAVIEW" ];then
		link_ThirdParty_package $PACKAGE $WM_ARCH$WM_COMPILER $PATH_TO_THIRDPARTY_PARAVIEW
	    fi

	    [ -n "$DOWNLOAD_ONLY" ] && return 0

	    if [ ! -d $ARCH_PATH ];then
		(cd $WM_THIRD_PARTY_DIR
		    source $WM_PROJECT_DIR/etc/bashrc $foam_settings
			
		    makeParaViewOptions="-qt \
-$QT_PACKAGE \
-cmake $WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/$CMAKE_PACKAGE \
-qmake $WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/$QT_PACKAGE/bin/qmake \
"
		    if [ $VERSION != "4.1.0" ];then
			if [ $PYTHON_TYPE = "ThirdParty" ];then
			    export PYTHON_INCLUDE=$PYTHON_ARCH_PATH/include/python$PYTHON_MAJOR_VERSION
			    export PATH=$PYTHON_ARCH_PATH/bin:$PATH
			    local PYTHON_OPTION="-python-lib $PYTHON_ARCH_PATH/lib/libpython$PYTHON_MAJOR_VERSION.so"
    			fi

			makeParaViewOptions="$makeParaViewOptions
-mpi \
-mesa \
-mesa-include $WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/$MESA_PACKAGE/include \
-mesa-lib $WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/$MESA_PACKAGE/lib/libOSMesa.so
-python $PYTHON_OPTION"

			local makeParaView=makeParaView
			if [ -x makeParaView4 ];then
			    makeParaView=makeParaView4
			fi
			chmod +x $makeParaView
			command="./$makeParaView $makeParaViewOptions"
			echo $command
			time $command
		    fi
		)
	    fi
	fi
    else
	echo "$PACKAGE is already installed in $ARCH_PATH"
    fi
}

build_ThirdParty()
{
    [ -n "$DOWNLOAD_ONLY" ] && return 0

    (cd $WM_THIRD_PARTY_DIR
	local sentinel="DONE_BUILD_THIRDPARTY_${COMPILER_TYPE}_${COMPILER}_${COMPILE_OPTION}_${PRECISION_OPTION}_${LABEL_SIZE}_${ARCH_OPTION}_${MPLIB}"
	if [ ! -f $sentinel ];then
	    . $FOAM_INST_DIR/OpenFOAM-$FOAM_VERSION/etc/bashrc $foam_settings
	    [ -n "$PLUS_VERSION" ] && options="-k"
	    time ./Allwmake $options && touch $sentinel
	else
	    echo "$WM_THIRD_PARTY_DIR is already built"
	fi
    )
}

build_OpenFOAM()
{
    [ -n "$DOWNLOAD_ONLY" ] && return 0

    (cd $WM_PROJECT_DIR
	local sentinel="DONE_BUILD_OPENFOAM_${COMPILER_TYPE}_${COMPILER}_${COMPILE_OPTION}_${PRECISION_OPTION}_${LABEL_SIZE}_${ARCH_OPTION}_${MPLIB}"

	if [ ! -f $sentinel ];then
	    . $FOAM_INST_DIR/OpenFOAM-$FOAM_VERSION/etc/bashrc $foam_settings
	    if [ $WM_COMPILER_TYPE = "system" ]
	    then
		export GMP_ARCH_PATH=$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH/$GMP_PACKAGE
		export MPFR_ARCH_PATH=$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH/$MPFR_PACKAGE
	    fi

	    if [ -n "$BUILD_FOAMY_HEX_MESH" ];then
		export FOAMY_HEX_MESH=yes
	    else
		unset FOAMY_HEX_MESH
	    fi

	    [ -n "$PLUS_VERSION" ] && options="-k"
	    time ./Allwmake $options && touch $sentinel
	else
	    echo "$WM_PROJECT_DIR is already built"
	fi
    )
}

#
# main
#

#- Laguage
LANG=C

#- Default
PATH_TO_THIRDPARTY_GCC=auto
PATH_TO_THIRDPARTY_GMP=auto
PATH_TO_THIRDPARTY_MPC=auto
PATH_TO_THIRDPARTY_MPFR=auto
PATH_TO_THIRDPARTY_BOOST=auto
PATH_TO_THIRDPARTY_CGAL=auto
PATH_TO_THIRDPARTY_CMAKE=auto
PATH_TO_THIRDPARTY_QT=auto
PATH_TO_THIRDPARTY_PYTHON=auto
PATH_TO_THIRDPARTY_MESA=auto
PATH_TO_THIRDPARTY_PARAVIEW=auto
PATH_TO_THIRDPARTY_OPENMPI=auto
unset SETTING_ONLY

#- Parse options
while [ "$#" -gt 0 ]
do
    case "$1" in
	-h | -help)
            usage
            ;;
	-gcc)
            [ "$#" -ge 2 ] || usage "'$1' option requires an argument"
            PATH_TO_THIRDPARTY_GCC=$2
            shift 2
            ;;
	-gmp)
            [ "$#" -ge 2 ] || usage "'$1' option requires an argument"
            PATH_TO_THIRDPARTY_GMP=$2
            shift 2
            ;;
	-mpfr)
            [ "$#" -ge 2 ] || usage "'$1' option requires an argument"
            PATH_TO_THIRDPARTY_MPFR=$2
            shift 2
            ;;
	-mpc)
            [ "$#" -ge 2 ] || usage "'$1' option requires an argument"
            PATH_TO_THIRDPARTY_MPC=$2
            shift 2
            ;;
	-boost)
            [ "$#" -ge 2 ] || usage "'$1' option requires an argument"
            PATH_TO_THIRDPARTY_BOOST=$2
            shift 2
            ;;
	-cgal)
            [ "$#" -ge 2 ] || usage "'$1' option requires an argument"
            PATH_TO_THIRDPARTY_CGAL=$2
            shift 2
            ;;
	-cmake)
            [ "$#" -ge 2 ] || usage "'$1' option requires an argument"
            PATH_TO_THIRDPARTY_CMAKE=$2
            shift 2
            ;;
	-qt)
            [ "$#" -ge 2 ] || usage "'$1' option requires an argument"
            PATH_TO_THIRDPARTY_QT=$2
            shift 2
            ;;
	-python)
            [ "$#" -ge 2 ] || usage "'$1' option requires an argument"
            PATH_TO_THIRDPARTY_PYTHON=$2
            shift 2
            ;;
	-mesa)
            [ "$#" -ge 2 ] || usage "'$1' option requires an argument"
            PATH_TO_THIRDPARTY_MESA=$2
            shift 2
            ;;
	-paraview)
            [ "$#" -ge 2 ] || usage "'$1' option requires an argument"
            PATH_TO_THIRDPARTY_PARAVIEW=$2
            shift 2
            ;;
	-openmpi)
            [ "$#" -ge 2 ] || usage "'$1' option requires an argument"
            PATH_TO_THIRDPARTY_OPENMPI=$2
            shift 2
            ;;
	*)
	    echo $*
            [ "$#" -ge 1 ] && usage ""
	    break
	    ;;
    esac
done

#- Source settings
. etc/system

[ -f system/$SYSTEM/bashrc ] || error "system/$SYSTEM/bashrc does not exist"
. system/$SYSTEM/bashrc

for OpenFOAM_BUILD_OPTION in ${OpenFOAM_BUILD_OPTION_LIST[@]}
do
    echo $OpenFOAM_BUILD_OPTION

    #- Log file name
    log=log.${OpenFOAM_BUILD_OPTION}

    OpenFOAM_VERSION=`echo $OpenFOAM_BUILD_OPTION | sed s/".*[,^]*OpenFOAM_VERSION=\([^,]*\).*$"/"\1"/`
    COMPILER_TYPE=`echo $OpenFOAM_BUILD_OPTION | sed s/".*[,^]*COMPILER_TYPE=\([^,]*\).*"/"\1"/`
    COMPILER=`echo $OpenFOAM_BUILD_OPTION | sed s/".*[,^]*COMPILER=\([^,]*\).*"/"\1"/`
    ARCH_OPTION=`echo $OpenFOAM_BUILD_OPTION | sed s/".*[,^]*ARCH_OPTION=\([^,]*\).*"/"\1"/`
    PRECISION_OPTION=`echo $OpenFOAM_BUILD_OPTION | sed s/".*[,^]*PRECISION_OPTION=\([^,]*\).*"/"\1"/`
    LABEL_SIZE=`echo $OpenFOAM_BUILD_OPTION | sed s/".*[,^]*LABEL_SIZE=\([^,]*\).*"/"\1"/`
    COMPILE_OPTION=`echo $OpenFOAM_BUILD_OPTION | sed s/".*[,^]*COMPILE_OPTION=\([^,]*\).*"/"\1"/`
    MPLIB=`echo $OpenFOAM_BUILD_OPTION | sed s/".*[,^]*MPLIB=\([^,]*\).*"/"\1"/`
    BUILD_PARAVIEW=`echo $OpenFOAM_BUILD_OPTION | sed s/".*[,^]*BUILD_PARAVIEW=\([^,]*\).*"/"\1"/`
    [ "$BUILD_PARAVIEW" != "1" ] && unset BUILD_PARAVIEW
    BUILD_FOAMY_HEX_MESH=`echo $OpenFOAM_BUILD_OPTION | sed s/".*[^,]*BUILD_FOAMY_HEX_MESH=\([^,]*\).*$"/"\1"/`
    [ "$BUILD_FOAMY_HEX_MESH" != "1" ] &&  unset BUILD_FOAMY_HEX_MESH
    DOWNLOAD_ONLY=`echo $OpenFOAM_BUILD_OPTION | sed s/".*[^,]*DOWNLOAD_ONLY=\([^,]*\).*$"/"\1"/`
    [ "$DOWNLOAD_ONLY" != "1" ] &&  unset DOWNLOAD_ONLY

    case "$OpenFOAM_VERSION" in
	OpenFOAM-v[0-9]*)
	    FOAM_VERSION=${OpenFOAM_VERSION#OpenFOAM-}
	    PLUS_VERSION=1
	    ;;
	OpenFOAM-[0-9]*)
	    FOAM_VERSION=${OpenFOAM_VERSION#OpenFOAM-}
	    unset PLUS_VERSION
	    ;;
	*)
	    echo "Unknown OpenFOAM version: $OpenFOAM_VERSION"
	    exit 1
	    ;;
    esac

#- Source function of download URL of software package
    . etc/url
    [ -f system/$SYSTEM/url ] && . system/$SYSTEM/url

#- Source function of package software version
    . etc/version
    [ -f system/$SYSTEM/version ] && . system/$SYSTEM/version

#- Compiler type and compiler
    COMPILER_WM_NAME=`echo $COMPILER | tr -d [:digit:]_`
    COMPILER_NAME=${COMPILER_WM_NAME%KNL}
    if [ $COMPILER_NAME = "Gcc" ];then
	GCC_VERSION=${COMPILER%KNL}
	GCC_VERSION=`echo ${GCC_VERSION#Gcc} | tr '_' '.'`
	GCC_PACKAGE=gcc-$GCC_VERSION
    else
    # dummy gcc for other compiler
	GCC_PACKAGE=gcc-4.0.0
    fi

#
#- Start building thirdparty software and OpenFOAM
#

# Make OpenFOAM directory
    [ -d $FOAM_INST_DIR ] || \
	mkdir $FOAM_INST_DIR  || \
	error "Could not make $FOAM_INST_DIR" 
    
    (
#- Allwmake settings
	foam_settings="\
foamCompiler=$COMPILER_TYPE \
WM_COMPILER_TYPE=$COMPILER_TYPE \
WM_COMPILER=$COMPILER \
WM_COMPILE_OPTION=$COMPILE_OPTION \
WM_PRECISION_OPTION=$PRECISION_OPTION \
WM_LABEL_SIZE=$LABEL_SIZE \
WM_ARCH_OPTION=$ARCH_OPTION \
WM_MPLIB=$MPLIB\
"
	echo "Build $OpenFOAM_VERSION under $foam_settings"

#- Source compiler and MPI library settings
	. system/$SYSTEM/settings
	
#- Directory
	WM_PROJECT_DIR=$FOAM_INST_DIR/OpenFOAM-$FOAM_VERSION
	WM_THIRD_PARTY_DIR=$FOAM_INST_DIR/ThirdParty-$FOAM_VERSION

#- Run function of each build step
	for function in \
	    download_and_extract_source \
	    patch_source \
	    build_Gcc \
	    add_wmake_rules \
	    build_CMake \
	    build_Qt \
	    build_Mesa \
	    build_Python \
	    download_CGAL \
	    download_Boost \
	    download_OpenMPI \
	    download_FFTW \
	    build_ThirdParty \
	    build_ParaView \
	    build_OpenFOAM
	do
	    echo "--------------------------------------------------------------------------------"
	    echo "Running $function"

	    $function 2>&1 || error "$function failed"

	    if [ ! -n "$DOWNLOAD_ONLY" -a $function = "build_Gcc" ];then
		. $FOAM_INST_DIR/OpenFOAM-$FOAM_VERSION/etc/bashrc $foam_settings
		echo "Build using $WM_NCOMPPROCS processor(s)."
	    fi

	done
	echo
	echo "End"
    ) > $log
done
