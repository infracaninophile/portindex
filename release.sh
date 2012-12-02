#!/bin/sh

# @(#) $Id$
#
# Tag the tree for release.  Export a clean copy of the files and
# build a tarball from that.  Add to the website repo, digitally sign
# etc.

export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export IFS=' 	
'
umask 022

WWWREPO="../html/portindex"

eval $(svn info | awk -F': ' '/^Repository Root:/ { print "SVNROOT="$2 }
                             /^URL:/ { print "SVNURL="$2 }')

TRUNK=$( echo $SVNURL | sed -e "s,$SVNROOT,," )
NAME=$(basename $TRUNK)

TEMPDIR=$( mktemp -d -t $(basename $0) ) || exit 1
trap "rm -rf $TEMPDIR; exit" EXIT INT KILL

VERSION=$( make -V VERSION )	# eg 3.0
RELEASETAG="RELEASE_$( echo -n $VERSION | tr -cs 0-9 _ )" # eg RELEASE_3_0

RELEASEBRANCH="/tags/${RELEASETAG}/${NAME}"


if svn info ^$RELEASEBRANCH >/dev/null 2>&1 ; then
   echo "$(basename $0): $RELEASEBRANCH already exists"
else
   svn copy --parents --message $RELEASETAG ^$TRUNK ^$RELEASEBRANCH || exit 1 
   echo "$(basename $0): Created release branch $RELEASEBRANCH"
fi

(
    cd $TEMPDIR
    svn export "${SVNROOT}${RELEASEBRANCH}" $NAME || exit 1
    cd $NAME && \
	perl Makefile.PL && \
	make dist COMPRESS=xz SUFFIX=.xz && \
	mv -v *.tar.xz ${TMPDIR:-/tmp}
)





