#!/bin/bash
set -e

PROG_NAME="EB Manager"
INSTALL_DIR=/usr/local/ebmanager
EXECUTABLES="ebm"
SYSTEM_BIN_DIR=/usr/local/bin

echo
echo "============================================================================================"
echo " ${PROG_NAME} Installer"
echo "============================================================================================"
echo

echo "Removing any previous installation"
rm -rf ${INSTALL_DIR}

echo "Installing into ${INSTALL_DIR}"
mkdir -p ${INSTALL_DIR}
tar -cf - . | (cd ${INSTALL_DIR} && tar -xpf -)

echo "Creating symlinks to executables in ${SYSTEM_BIN_DIR}"
for EXECUTABLE in ${EXECUTABLES}
do
  chmod ugo+x ${INSTALL_DIR}/${EXECUTABLE}
  rm -f ${SYSTEM_BIN_DIR}/${EXECUTABLE##*/}
  ln -sf ${INSTALL_DIR}/${EXECUTABLE} ${SYSTEM_BIN_DIR}/${EXECUTABLE##*/}
done

echo "Done"
echo

exit
