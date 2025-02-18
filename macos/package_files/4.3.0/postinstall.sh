#! /bin/bash
# By Spransy, Derek" <DSPRANS () emory ! edu> and Charlie Scott
# Modified by Santiago Bassett (http://www.wazuh.com) - Feb 2016
# alterations by bil hays 2013
# -Switched to bash
# -Added some sanity checks
# -Added routine to find the first 3 contiguous UIDs above 100,
#  starting at 600 puts this in user space
# -Added lines to append the ossec users to the group ossec
#  so the the list GroupMembership works properly
GROUP="wazuh"
USER="wazuh"
DIR="/Library/Ossec"
INSTALLATION_SCRIPTS_DIR="${DIR}/packages_files/agent_installation_scripts"
SCA_BASE_DIR="${INSTALLATION_SCRIPTS_DIR}/sca"

if [ $(launchctl getenv WAZUH_PKG_UPGRADE) = true ]; then
    rm -rf ${DIR}/etc/{ossec.conf,client.keys,local_internal_options.conf,shared}
    cp -rf ${DIR}/config_files/{ossec.conf,client.keys,local_internal_options.conf,shared} ${DIR}/etc/
    rm -rf ${DIR}/config_files/
fi

# Default for all directories
chmod -R 750 ${DIR}/
chown -R root:${GROUP} ${DIR}/

chown -R root:wheel ${DIR}/bin
chown -R root:wheel ${DIR}/lib

# To the ossec queue (default for agentd to read)
chown -R ${USER}:${GROUP} ${DIR}/queue/{alerts,diff,sockets,rids}

chmod -R 770 ${DIR}/queue/{alerts,sockets}
chmod -R 750 ${DIR}/queue/{diff,sockets,rids}

# For the logging user
chmod 770 ${DIR}/logs
chown -R ${USER}:${GROUP} ${DIR}/logs
find ${DIR}/logs/ -type d -exec chmod 750 {} \;
find ${DIR}/logs/ -type f -exec chmod 660 {} \;

chown -R root:${GROUP} ${DIR}/tmp
chmod 1750 ${DIR}/tmp

chmod 770 ${DIR}/etc
chown ${USER}:${GROUP} ${DIR}/etc
chmod 640 ${DIR}/etc/internal_options.conf
chown root:${GROUP} ${DIR}/etc/internal_options.conf
chmod 640 ${DIR}/etc/local_internal_options.conf
chown root:${GROUP} ${DIR}/etc/local_internal_options.conf
chmod 640 ${DIR}/etc/client.keys
chown root:${GROUP} ${DIR}/etc/client.keys
chmod 640 ${DIR}/etc/localtime
chmod 770 ${DIR}/etc/shared # ossec must be able to write to it
chown -R root:${GROUP} ${DIR}/etc/shared
find ${DIR}/etc/shared/ -type f -exec chmod 660 {} \;
chown root:${GROUP} ${DIR}/etc/ossec.conf
chmod 660 ${DIR}/etc/ossec.conf
chown root:${GROUP} ${DIR}/etc/wpk_root.pem
chmod 640 ${DIR}/etc/wpk_root.pem


chmod 770 ${DIR}/.ssh

# For the /var/run
chmod -R 770 ${DIR}/var
chown -R root:${GROUP} ${DIR}/var

. ${INSTALLATION_SCRIPTS_DIR}/src/init/dist-detect.sh

upgrade=$(launchctl getenv WAZUH_PKG_UPGRADE)
restart=$(launchctl getenv WAZUH_RESTART)

launchctl unsetenv WAZUH_PKG_UPGRADE
launchctl unsetenv WAZUH_RESTART

if [ "${upgrade}" = "false" ]; then
    ${INSTALLATION_SCRIPTS_DIR}/gen_ossec.sh conf agent ${DIST_NAME} ${DIST_VER}.${DIST_SUBVER} ${DIR} > ${DIR}/etc/ossec.conf
    chown root:wazuh ${DIR}/etc/ossec.conf
    chmod 0640 ${DIR}/etc/ossec.conf
fi

SCA_DIR="${DIST_NAME}/${DIST_VER}"
mkdir -p ${DIR}/ruleset/sca

SCA_TMP_DIR="${SCA_BASE_DIR}/${SCA_DIR}"

# Install the configuration files needed for this hosts
if [ -r "${SCA_BASE_DIR}/${DIST_NAME}/${DIST_VER}/${DIST_SUBVER}/sca.files" ]; then
    SCA_TMP_DIR="${SCA_BASE_DIR}/${DIST_NAME}/${DIST_VER}/${DIST_SUBVER}"
elif [ -r "${SCA_BASE_DIR}/${DIST_NAME}/${DIST_VER}/sca.files" ]; then
    SCA_TMP_DIR="${SCA_BASE_DIR}/${DIST_NAME}/${DIST_VER}"
elif [ -r "${SCA_BASE_DIR}/${DIST_NAME}/sca.files" ]; then
    SCA_TMP_DIR="${SCA_BASE_DIR}/${DIST_NAME}"
else
    SCA_TMP_DIR="${SCA_BASE_DIR}/generic"
fi

SCA_TMP_FILE="${SCA_TMP_DIR}/sca.files"

if [ -r ${SCA_TMP_FILE} ]; then

    rm -f ${DIR}/ruleset/sca/* || true

    for sca_file in $(cat ${SCA_TMP_FILE}); do
        mv ${SCA_BASE_DIR}/${sca_file} ${DIR}/ruleset/sca
    done
fi

# Register and configure agent if Wazuh environment variables are defined
${INSTALLATION_SCRIPTS_DIR}/src/init/register_configure_agent.sh ${DIR} > /dev/null || :

# Install the service
${INSTALLATION_SCRIPTS_DIR}/src/init/darwin-init.sh ${DIR}

# Remove temporary directory
rm -rf ${DIR}/packages_files

# Remove old ossec user and group if exists and change ownwership of files

if [[ $(dscl . -read /Groups/ossec) ]]; then
  find %{_localstatedir} -group ossec -user root -exec chown root:wazuh {} \ > /dev/null 2>&1 || true
  if [ $(dscl . -read /Users/ossec) ]]; then
    find %{_localstatedir} -group ossec -user ossec -exec chown wazuh:wazuh {} \ > /dev/null 2>&1 || true
    sudo /usr/bin/dscl . -delete "/Users/ossec"
  fi
  if [ $(dscl . -read /Users/ossecm) ]]; then
    find %{_localstatedir} -group ossec -user ossecm -exec chown wazuh:wazuh {} \ > /dev/null 2>&1 || true
    sudo /usr/bin/dscl . -delete "/Users/ossecm"
  fi
  if [ $(dscl . -read /Users/ossecr) ]]; then
    find %{_localstatedir} -group ossec -user ossecr -exec chown wazuh:wazuh {} \ > /dev/null 2>&1 || true
    sudo /usr/bin/dscl . -delete "/Users/ossecr"
  fi
  sudo /usr/bin/dscl . -delete "/Groups/wazuh"
fi

# Remove 4.1.5 patch
if [ -f ${DIR}/queue/alerts/sockets ]; then
  rm ${DIR}/queue/alerts/sockets
fi

if ${upgrade} && ${restart}; then
    ${DIR}/bin/wazuh-control restart
fi
