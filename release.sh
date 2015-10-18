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

WWWREPO="~/src/html/portindex"

GIT_ORIGIN=$(git config --get remote.origin.url)

NAME=${GIT_ORIGIN##*/}
NAME=${NAME%.git}

TEMPDIR=$( mktemp -d -t $(basename $0) ) || exit 1
trap "rm -rf $TEMPDIR; exit" EXIT INT KILL

set -e
[ -f Makefile ] && make clean
perl Makefile.PL
make

VERSION=$( make -V VERSION )	# eg 3.0
: ${VERSION:?"Can't determine the release version"}

RELEASETAG="RELEASE_$( echo -n $VERSION | tr -cs 0-9 _ )" # eg RELEASE_3_0

if git tag -l | grep -q ^$RELEASETAG ; then
    echo "$(basename $0): $RELEASETAG already exists"
else
    git tag -s -f -m "Release $VERSION" $RELEASETAG
    ##git push --follow-tags
    echo "$(basename $0): Created release tag $RELEASETAG"
fi

(
    cd $TEMPDIR
    git clone $GIT_ORIGIN $NAME || exit 1
    cd $NAME && \
	git checkout tags/$RELEASETAG -- && \
	perl Makefile.PL && \
	make dist COMPRESS=xz SUFFIX=.xz && \
	mv -v *.tar.xz ${TMPDIR:-/tmp}
)





