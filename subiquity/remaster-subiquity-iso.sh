#!/bin/bash
# set -x

iso_url="https://releases.ubuntu.com/21.04/ubuntu-21.04-live-server-amd64.iso"
sha_url="https://releases.ubuntu.com/21.04/SHA256SUMS"

# You may want to change this path, everything happens below this location
work_dir=/tmp/remaster
mkdir -p ${work_dir}
iso_tmp="$(mktemp -d -p ${work_dir})"
iso_file=$(basename ${iso_url})

# fetch the iso, using wget, because we can resume
wget -c "${iso_url}" -q --show-progress -P "${work_dir}"

# Check the SHA256SUM before continuing, bail out if exit 1
echo -n "Checking integrity of the downloaded iso image... "
grep "${iso_file}" <(wget -q "${sha_url}" -O -) | sha256sum --check

sudo mount -oloop "${work_dir}/${iso_file}" "${iso_tmp}"

echo "Image is now mounted at ${iso_tmp} ..."

squash_tmp_dir=$(mktemp -d -p ${work_dir})
squash_out_dir=$(mktemp -d -p ${work_dir})
echo "Unpacking 'filesystem.squashfs' into ${squash_tmp_dir} to inject 'answers.yaml' "
sudo unsquashfs -f -d "${squash_tmp_dir}" "${iso_tmp}"/casper/filesystem.squashfs
sudo mkdir -p "${squash_tmp_dir}"/subiquity_config

# shellcheck disable=SC2154,SC1037
sudo tee "${squash_tmp_dir}"/subiquity_config/answers.yaml << EOF 
Welcome:
  lang: en_US
Refresh:
  update: yes
Keyboard:
  layout: us
Zdev:
  accept-default: yes
Network:
  accept-default: yes
Proxy:
  proxy: ""
Mirror:
  country-code: us
Filesystem:
  guided: yes
  guided-index: 0
Identity:
  realname: Ubuntu User
  username: ubuntu
  hostname: lego-four
  password: '\$6\$wdAcoXrU039hKYPd\$508Qvbe7ObUnxoj15DRCkzC3qO7edjH0VV7BPNRDYK4QR8ofJaEEF2heacn0QgD.f8pO8SNp83XNdWG6tocBM1'
  ssh-import-id: gh:desrod
SSH:
  install_server: true
  pwauth: true
SnapList:
  snaps:
    hello:
      channel: stable
      is_classic: false
InstallProgress:
  reboot: yes
EOF

# sudo cp "${work_dir}"/answers.yaml "${squash_tmp_dir}"/subiquity_config
sudo mksquashfs "${squash_tmp_dir}" "${squash_out_dir}"/filesystem.squashfs

# This is better handled as an overlay unionfs/aufs mount, vs. rsync'ing data around
sudo rsync -aqP --inplace --partial "${iso_tmp}"/. "${work_dir}"/final/
sudo rsync -aqP --inplace --partial "${squash_out_dir}"/filesystem.squashfs "${work_dir}"/final/casper/

# Cleanup
sudo rm -rf "${squash_tmp_dir}"
sudo umount "${iso_tmp}"
sudo rm -rf "${iso_tmp}" "${squash_out_dir}"

iso_opts="$(xorriso -indev "${iso_file}" -report_el_torito as_mkisofs)"
# shellcheck disable=SC2086
eval set -- ${iso_opts}
xorriso -as mkisofs "$@" -o ${work_dir}/subiquity-remaster-"$(date +%Y-%m-%d)".iso -V 'Subiquity Remaster' "${work_dir}"/final

sudo rm -rf "${work_dir}"/final