TERMUX_PKG_HOMEPAGE=https://www.haskell.org/ghc/
TERMUX_PKG_DESCRIPTION="The Glasgow Haskell Compiler libraries"
TERMUX_PKG_LICENSE="custom"
TERMUX_PKG_MAINTAINER="Aditya Alok <alok@termux.dev>"
TERMUX_PKG_VERSION=9.12.1
TERMUX_PKG_SRCURL="https://downloads.haskell.org/~ghc/$TERMUX_PKG_VERSION/ghc-$TERMUX_PKG_VERSION-src.tar.xz"
TERMUX_PKG_SHA256=4a7410bdeec70f75717087b8f94bf5a6598fd61b3a0e1f8501d8f10be1492754
TERMUX_PKG_DEPENDS="libiconv, libffi, libgmp, libandroid-posix-semaphore"
TERMUX_PKG_BUILD_DEPENDS="dnsutils"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
--host=$TERMUX_BUILD_TUPLE
--with-system-libffi"
TERMUX_PKG_NO_STATICSPLIT=true
TERMUX_PKG_REPLACES="ghc-libs-static"

termux_step_post_get_source() {
	termux_setup_ghc && termux_setup_cabal
	cabal update
}

termux_step_pre_configure() {
	export CONF_CC_OPTS_STAGE1="$CFLAGS $CPPFLAGS" CONF_GCC_LINKER_OPTS_STAGE1="$LDFLAGS"
	export CONF_CC_OPTS_STAGE2="$CFLAGS $CPPFLAGS" CONF_GCC_LINKER_OPTS_STAGE2="$LDFLAGS"
	# export CONF_GCC_SUPPORTS_NO_PIE=NO # Linker says it does, but Android > 5.0 cannot run them.

	export target="$TERMUX_HOST_PLATFORM"
	if [ "$TERMUX_ARCH" = "arm" ]; then
		target="armv7a-linux-androideabi"
	fi
	TERMUX_PKG_EXTRA_CONFIGURE_ARGS+=" --target=$target"

	./boot.source
}

termux_step_make() {
	termux_setup_ghc && termux_setup_cabal
	(
		# XXX: Temporary

		unset CFLAGS CPPFLAGS LDFLAGS # For stage0 compilation.

		./hadrian/build binary-dist-dir -j --flavour=quickest+no_profiled_libs --docs=none \
			"stage1.*.ghc.*.opts += -optl-landroid-posix-semaphore" \
			"stage2.*.ghc.*.opts += -optl-landroid-posix-semaphore"
	)
}

__setup_proot_and_qemu() {
	mkdir -p "$TERMUX_PKG_CACHEDIR"/bin

	termux_download https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-x86_64-static \
		"$TERMUX_PKG_CACHEDIR/bin"/proot \
		d1eb20cb201e6df08d707023efb000623ff7c10d6574839d7bb42d0adba6b4da

	if [[ "$TERMUX_ARCH" == "aarch64" ]]; then
		termux_download https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static \
			"$TERMUX_PKG_CACHEDIR/bin"/qemu-static \
			dce64b2dc6b005485c7aa735a7ea39cb0006bf7e5badc28b324b2cd0c73d883f
	elif [[ "$TERMUX_ARCH" == "arm" ]]; then
		termux_download https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-arm-static \
			"$TERMUX_PKG_CACHEDIR/bin"/qemu-static \
			9f07762a3cd0f8a199cb5471a92402a4765f8e2fcb7fe91a87ee75da9616a806
	fi

	chmod +x "$TERMUX_PKG_CACHEDIR"/bin/{proot,qemu-static}
}

__setup_termux_rootfs() {
	termux_download https://raw.githubusercontent.com/NotGlop/docker-drag/5413165a2453aa0bc275d7dc14aeb64e814d5cc0/docker_pull.py \
		"$TERMUX_PKG_CACHEDIR"/docker_pull.py \
		04e52b70c862884e75874b2fd229083fdf09a4bac35fc16fd7a0874ba20bd075
	termux_download https://raw.githubusercontent.com/larsks/undocker/649f3fdeb0a9cf8aa794d90d6cc6a7c7698a25e6/undocker.py \
		"$TERMUX_PKG_CACHEDIR"/undocker.py \
		32bc122c53153abeb27491e6d45122eb8cef4f047522835bedf9b4b87877a907

	(
		cd "$TERMUX_PKG_CACHEDIR"

		if [[ ! -f termux_"$TERMUX_ARCH"_termux-docker.tar ]]; then
			python docker_pull.py termux/termux-docker:"$TERMUX_ARCH"
			mv termux_termux-docker.tar termux_"$TERMUX_ARCH"_termux-docker.tar
		fi
		python undocker.py -o "$TERMUX_ROOTFS" <termux_"$TERMUX_ARCH"_termux-docker.tar
		# mv -f "$TERMUX_ROOTFS$TERMUX_PREFIX" "$TERMUX_ROOTFS$TERMUX_PREFIX.guest-prefix" &>/dev/null || :
	)

	cp "$TERMUX_PKG_BUILDER_DIR"/static-dns-hosts.txt "$TERMUX_ROOTFS"/system/etc/
	cp "$TERMUX_PKG_BUILDER_DIR"/update-static-dns "$TERMUX_ROOTFS"/
	chmod +x "$TERMUX_ROOTFS"/update-static-dns
}

termux_step_make_install() {
	export TERMUX_ROOTFS="$TERMUX_PKG_TMPDIR/$TERMUX_ARCH-termux-rootfs"

	__setup_proot_and_qemu
	__setup_termux_rootfs

	local proot_qemu=""
	if [[ "$TERMUX_ARCH" == "aarch64" ]] || [[ "$TERMUX_ARCH" == "arm" ]]; then
		proot_qemu="-q $TERMUX_PKG_CACHEDIR/bin/qemu-static"
	fi

	# $__proot_cmd bash
	# XXX: Temporary
	export target="$TERMUX_HOST_PLATFORM"
	if [ "$TERMUX_ARCH" = "arm" ]; then
		target="armv7a-linux-androideabi"
	fi

	__proot_cmd="env -i
	PATH=$TERMUX_PREFIX/bin:/host-termux-prefix/bin
	LD_LIBRARY_PATH=/host-termux-prefix/lib
	$TERMUX_PKG_CACHEDIR/bin/proot
	-b $TERMUX_PKG_SRCDIR/_build/bindist:/ghc-bindist
	-b $TERMUX_PREFIX:/host-termux-prefix
	$proot_qemu -R $TERMUX_ROOTFS -w /ghc-bindist/ghc-$TERMUX_PKG_VERSION-$target"

	$__proot_cmd /update-static-dns
	$__proot_cmd apt update
	$__proot_cmd apt upgrade -yq -o Dpkg::Options::=--force-confnew
	$__proot_cmd pkg i clang ndk-multilib binutils-is-llvm make -y
	$__proot_cmd env CC="clang" CXX="clang++" LD="ld.lld" AR="llvm-ar" NM="llvm-nm" STRIP="llvm-strip" ./configure --prefix=/host-termux-prefix --build="$target"
	$__proot_cmd make install

	sed -i "s|/host-termux-prefix|$TERMUX_PREFIX|g" "$TERMUX_PREFIX"/bin/"$target"-{ghc,ghc-pkg,hsc2hs-ghc,hp2ps-ghc,ghci}-"$TERMUX_PKG_VERSION"

	# We may build GHC with `llc-9` etc., but only `llc` is present in Termux
	# sed -i 's/"LLVM llc command", "llc.*"/"LLVM llc command", "llc"/' \
	# 	"$TERMUX_PREFIX/lib/$target-ghc-$TERMUX_PKG_VERSION/lib/settings" || :
	# sed -i 's/"LLVM opt command", "opt.*"/"LLVM opt command", "opt"/' \
	# 	"$TERMUX_PREFIX/lib/$target-ghc-$TERMUX_PKG_VERSION/lib/settings" || :
}

termux_step_install_license() {
	install -Dm600 -t "$TERMUX_PREFIX/share/doc/$TERMUX_PKG_NAME" \
		"$TERMUX_PKG_SRCDIR/LICENSE"
}
