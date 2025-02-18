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
--with-system-libffi
--disable-ld-override"
TERMUX_PKG_REPLACES="ghc-libs-static"
TERMUX_PKG_NO_STATICSPLIT=true

termux_step_pre_configure() {
	termux_setup_ghc && termux_setup_cabal

	export CONF_CC_OPTS_STAGE1="$CFLAGS $CPPFLAGS"
	export CONF_GCC_LINKER_OPTS_STAGE1="$LDFLAGS"
	export CONF_CXX_OPTS_STAGE1="$CXXFLAGS"

	export CONF_CC_OPTS_STAGE2="$CFLAGS $CPPFLAGS"
	export CONF_GCC_LINKER_OPTS_STAGE2="$LDFLAGS"
	export CONF_CXX_OPTS_STAGE2="$CXXFLAGS"

	export target="$TERMUX_HOST_PLATFORM"
	export flavour="release+split_sections"

	if [ "$TERMUX_ARCH" = "arm" ]; then
		target="armv7a-linux-androideabi"
		# Do not build profiled libs for `arm`. It exceeds the 6 hours limit of github CI.
		flavour="${flavour}+no_profiled_libs"
	elif [ "$TERMUX_ARCH" = "i686" ]; then
		# WARNING: This should make it support `i686`, but it needs testing.
		sed -i -E 's|"i686-unknown-linux"|"i686-unknown-linux-android"|' llvm-targets
	fi

	TERMUX_PKG_EXTRA_CONFIGURE_ARGS="$TERMUX_PKG_EXTRA_CONFIGURE_ARGS --target=$target"
}

termux_step_make() {
	(
		unset CFLAGS CPPFLAGS LDFLAGS # For stage0 compilation.
		./hadrian/build binary-dist-dir -j"$TERMUX_PKG_MAKE_PROCESSES" --flavour="$flavour" --docs=none \
			"stage1.unix.ghc.link.opts += -optl-landroid-posix-semaphore" \
			"stage2.unix.ghc.link.opts += -optl-landroid-posix-semaphore"
		#	"stage2.ghc-bin.ghc.link.opts += -optl-landroid-posix-semaphore"
	)
}

termux_step_make_install() {
	cd _build/bindist/ghc-"$TERMUX_PKG_VERSION"-"$target" || exit 1

	# We need to re-run configure:
	# See: https://gitlab.haskell.org/ghc/ghc/-/issues/22058
	./configure \
		--prefix="$TERMUX_PREFIX" \
		--with-system-libffi \
		--disable-ld-override \
		--host="$target"

	HOST_GHC_PKG="$(realpath ../../stage1/bin/"$target"-ghc-pkg)" make install
}

termux_step_install_license() {
	install -Dm600 -t "$TERMUX_PREFIX/share/doc/$TERMUX_PKG_NAME" \
		"$TERMUX_PKG_SRCDIR/LICENSE"
}

termux_step_post_massage() {
	# Remove cross-prefix from binaries and fix links:
	for path in bin/"$target"-*; do
		newpath="${path//$target-/}"

		if [ -h "$path" ]; then
			link_target="$(readlink "$path")"
			ln -sf "${link_target//$target-/}" "$newpath"
			rm "$path"
		else
			mv "$path" "$newpath"
		fi

	done

	local ghclibs_dir="lib/$target-ghc-$TERMUX_PKG_VERSION"

	if ! [ -d "$ghclibs_dir" ]; then
		echo "ERROR: GHC lib directory is not at expected place. Please verify before updating."
		exit 1
	fi

	# We may build GHC with `{llc,opt}-<version suffix>`, but only `llc`,`opt` is present in Termux:
	sed -i -E 's|("LLVM llc command",) "llc.*"|\1 "llc"|' "$ghclibs_dir"/lib/settings
	sed -i -E 's|("LLVM opt command",) "opt.*"|\1 "opt"|' "$ghclibs_dir"/lib/settings

	# Remove cross-prefix from settings:
	# Why? Since we will use native compiler on the target, we don't need it.
	sed -i "s|${target}-||g" "$ghclibs_dir"/lib/settings

	# The second `configure` script was ment to be run on host(=target) but we are running
	# on CI, therefore we need to remove cross compiler flag:
	sed -i -E 's|("cross compiling",) "YES"|\1 "NO"|' "$ghclibs_dir"/lib/settings

	find . -type f \( -name "*.so" -o -name "*.a" \) -exec "$STRIP" --strip-unneeded {} \;
	find "$ghclibs_dir"/bin -type f -exec "$STRIP" {} \;
}
