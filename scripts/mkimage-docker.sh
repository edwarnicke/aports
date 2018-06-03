#!/bin/sh -e

usage() {
        cat <<EOF

$0  [--tag RELEASE] [--outdir OUTDIR] [--workdir WORKDIR]
        [--arch ARCH] [--profile PROFILE] [--hostkeys] [--simulate]
        [--repository REPO] [--extra-repository REPO] [--yaml FILE]
$0  --help

options:
--arch          Specify which architecture images to build
            (default: $default_arch)
--hostkeys      Copy system apk signing keys to created images
--outdir        Specify directory for the created images
--profile       Specify which profiles to build
--repository        Package repository to use for the image create
--extra-repository  Add repository to search packages from
--simulate      Don't execute commands
--tag           Build images for tag RELEASE
--workdir       Specify temporary working directory (cache)
--yaml
--version       Specify alpine version (edge,v3.7,etc)

known profiles: $(echo $all_profiles | sort -u)

EOF
}

origargs="$@"
# parse parameters
while [ $# -gt 0 ]; do
    opt="$1"
    shift
    case "$opt" in
    --repository)
        if [ -z "$REPOS" ]; then
            REPOS="$1"
        else
            REPOS=$(printf '%s\n%s' "$REPOS" "$1");
        fi
        shift ;;
    --extra-repository) EXTRAREPOS="$EXTRAREPOS $1"; shift ;;
    --workdir) WORKDIR="$1"; shift ;;
    --outdir) OUTDIR="$1"; shift ;;
    --tag) RELEASE="$1"; shift ;;
    --arch) req_arch="$1"; shift ;;
    --profile) req_profiles="$1"; shift ;;
    --hostkeys) _hostkeys="--hostkeys";;
    --simulate) _simulate="yes";;
    --checksum) _checksum="yes";;
    --yaml) _yaml="yes";;
    --version) _version=$1;shift;;
    --) break ;;
    -*) usage; exit 1;;
    esac
done

_version=${_version:-edge}

if [ -z ${REPOS} ]; then
    origargs="${origargs} --repository http://dl-cdn.alpinelinux.org/alpine/${_version}/main"
fi
output_filename=mkimage_output${req_arch:+"-${req_arch}"}${req_profiles:+"-${req_profiles}"}
TMPDIR=$(mktemp -d)
echo "TMPDIR: ${TMPDIR}"
DOCKER_FILE=${TMPDIR}/Dockerfile
cat > ${DOCKER_FILE} << EOF
FROM multiarch/alpine:${req_arch}-${_version}
RUN uname -a
RUN apk update \
    && apk add build-base git sudo \
        fakeroot alpine-sdk alpine-base linux-firmware linux-rpi2
RUN addgroup root abuild
COPY . /root/git/aports/
ENV output_filename=${output_filename}
RUN cd /root/git/aports/scripts && ./mkimage.sh ${origargs}
EOF
docker run --rm --privileged multiarch/qemu-user-static:register --reset
docker build -f ${DOCKER_FILE} $(dirname $0)/../ | tee ${TMPDIR}/log
IMAGE=$(cat ${TMPDIR}/log | grep "^Successfully built" | awk '{print $3}')
echo "IMAGE: ${IMAGE}"
CONTAINER=$(docker create -it ${IMAGE} /usr/bin/tail -f /dev/null)
docker cp ${CONTAINER}:/root/git/aports/scripts/${output_filename} .
docker rm ${CONTAINER}
echo "output: ${output_filename}"

