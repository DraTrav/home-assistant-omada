#!/usr/bin/env bashio

# =====================================
# Home Assistant specific preprocessing
# =====================================

# create data and logs dir, if not existing
bashio::log.info "Create 'logs' directory inside persistent /data volume, if it doesn't exist."
mkdir -p "/data/logs"

if [ ! -d /data/data ]; then
  bashio::log.info "/data/data created from docker image backup" && cp -r /opt/tplink/EAPController/data_backup /data/data

  # Check if old directory structure is in place (/data) and copy to (/data/data)
  # This can be removed in the future when everyone has upgraded
  directories=(db keystore pdf)
  for dir in "${directories[@]}"; do
    if [ -d "/data/$dir" ]; then
      cp -r /data/$dir "/data/data/"
      rm -rf /data/$dir
      bashio::log.info "Migrate from old Add-On file structure. Copied /data/$dir to /data/data/$dir"
    else
      bashio::log.info "Already in new file structure. /data/$dir does not exist, skipping."
    fi
  done
fi

# set permissions on /data directory for home assistant persistence
chown -R 508:508 "/data"

# Use SSL Keys from Home Assistant
if bashio::config.true 'enable_hass_ssl'; then
  bashio::log.info "Use SSL from Home Assistant"
  SSL_CERT_NAME=$(bashio::config 'certfile')
  bashio::log.info "SSL certificate: ${SSL_CERT_NAME}"
  SSL_KEY_NAME=$(bashio::config 'keyfile')
  bashio::log.info "SSL private key: ${SSL_KEY_NAME}"
fi

# ======================================
# mbentley original entrypoint.sh script
# ======================================
#
# Replace this section if needed during updates.
#
# IMPORTANT: to enable pretty logs, replace all
#   - `^(\s*)echo\s*"INFO: `     with    `$1bashio::log.info "`
#   - `^(\s*)echo\s*"WARNING: `  with    `$1bashio::log.warning "`
#   - `^(\s*)echo\s*"ERROR: `    with    `$1bashio::log.error "`
#
# > Script start
# -------------------------------------------------------------------------------------------------------------------------------------------------------------------

# set environment variables
export TZ
TZ="${TZ:-Etc/UTC}"
SMALL_FILES="${SMALL_FILES:-false}"

# PORTS CONFIGURATION
MANAGE_HTTP_PORT="${MANAGE_HTTP_PORT:-8088}"
MANAGE_HTTPS_PORT="${MANAGE_HTTPS_PORT:-8043}"
PORTAL_HTTP_PORT="${PORTAL_HTTP_PORT:-8088}"
PORTAL_HTTPS_PORT="${PORTAL_HTTPS_PORT:-8843}"
PORT_ADOPT_V1="${PORT_ADOPT_V1:-29812}"
PORT_APP_DISCOVERY="${PORT_APP_DISCOVERY:-27001}"
PORT_UPGRADE_V1="${PORT_UPGRADE_V1:-29813}"
PORT_MANAGER_V1="${PORT_MANAGER_V1:-29811}"
PORT_MANAGER_V2="${PORT_MANAGER_V2:-29814}"
PORT_DISCOVERY="${PORT_DISCOVERY:-29810}"
PORT_TRANSFER_V2="${PORT_TRANSFER_V2:-29815}"
PORT_RTTY="${PORT_RTTY:-29816}"
# END PORTS CONFIGURATION

# EXTERNAL MONGODB
MONGO_EXTERNAL="${MONGO_EXTERNAL:-false}"
EAP_MONGOD_URI="${EAP_MONGOD_URI:-mongodb://127.0.0.1:27217/omada}"
# escape & for eval
EAP_MONGOD_URI="$(eval echo "${EAP_MONGOD_URI//&/\\&}")"
# escape after eval as well for sed
EAP_MONGOD_URI="${EAP_MONGOD_URI//&/\\&}"
# END EXTERNAL MONGODB

SHOW_SERVER_LOGS="${SHOW_SERVER_LOGS:-true}"
SHOW_MONGODB_LOGS="${SHOW_MONGODB_LOGS:-false}"
SSL_CERT_NAME="${SSL_CERT_NAME:-tls.crt}"
SSL_KEY_NAME="${SSL_KEY_NAME:-tls.key}"
TLS_1_11_ENABLED="${TLS_1_11_ENABLED:-false}"
PUID="${PUID:-508}"
PGID="${PGID:-508}"
PUSERNAME="${PUSERNAME:-omada}"
PGROUP="${PGROUP:-omada}"
SKIP_USERLAND_KERNEL_CHECK="${SKIP_USERLAND_KERNEL_CHECK:-false}"

# validate user/group exist with correct UID/GID
bashio::log.info "Validating user/group (${PUSERNAME}:${PGROUP}) exists with correct UID/GID (${PUID}:${PGID})"

# check to see if group exists; if not, create it
if grep -q -E "^${PGROUP}:" /etc/group > /dev/null 2>&1
then
  # existing group found; also make sure the omada group matches the GID
  bashio::log.info "Group (${PGROUP}) exists; skipping creation"
  EXISTING_GID="$(getent group "${PGROUP}" | cut -d: -f3)"
  if [ "${EXISTING_GID}" != "${PGID}" ]
  then
    bashio::log.error "Group (${PGROUP}) has an unexpected GID; was expecting '${PGID}' but found '${EXISTING_GID}'!"
    exit 1
  fi
else
  # make sure the group doesn't already exist with a different name
  if awk -F ':' '{print $3}' /etc/group | grep -q "^${PGID}$"
  then
    # group ID exists but has a different group name
    EXISTING_GROUP="$(grep ":${PGID}:" /etc/group | awk -F ':' '{print $1}')"
    bashio::log.info "Group (${PGROUP}) already exists with a different name; renaming '${EXISTING_GROUP}' to '${PGROUP}'"
    groupmod -n "${PGROUP}" "${EXISTING_GROUP}"
  else
    # create the group
    bashio::log.info "Group (${PGROUP}) doesn't exist; creating"
    groupadd -g "${PGID}" "${PGROUP}"
  fi
fi

# check to see if user exists; if not, create it
if id -u "${PUSERNAME}" > /dev/null 2>&1
then
  # exiting user found; also make sure the omada user matches the UID
  bashio::log.info "User (${PUSERNAME}) exists; skipping creation"
  EXISTING_UID="$(id -u "${PUSERNAME}")"
  if [ "${EXISTING_UID}" != "${PUID}" ]
  then
    bashio::log.error "User (${PUSERNAME}) has an unexpected UID; was expecting '${PUID}' but found '${EXISTING_UID}'!"
    exit 1
  fi
else
  # make sure the user doesn't already exist with a different name
  if awk -F ':' '{print $3}' /etc/passwd | grep -q "^${PUID}$"
  then
    # user ID exists but has a different user name
    EXISTING_USER="$(grep ":${PUID}:" /etc/passwd | awk -F ':' '{print $1}')"
    bashio::log.info "User (${PUSERNAME}) already exists with a different name; renaming '${EXISTING_USER}' to '${PUSERNAME}'"
    usermod -g "${PGID}" -d /opt/tplink/EAPController/data -l "${PUSERNAME}" -s /bin/sh -c "" "${EXISTING_USER}"
  else
    # create the user
    bashio::log.info "User (${PUSERNAME}) doesn't exist; creating"
    useradd -u "${PUID}" -g "${PGID}" -d /opt/tplink/EAPController/data -s /bin/sh -c "" "${PUSERNAME}"
  fi
fi

# check if properties file exists; create it if it is missing
DEFAULT_FILES="/opt/tplink/EAPController/properties.defaults/*"
for FILE in ${DEFAULT_FILES}
do
  BASENAME=$(basename "${FILE}")
  if [ ! -f "/opt/tplink/EAPController/properties/${BASENAME}" ]
  then
    bashio::log.info "Properties file '${BASENAME}' missing, restoring default file..."
    cp "${FILE}" "/opt/tplink/EAPController/properties/${BASENAME}"
    chown "${PUSERNAME}:${PGROUP}" "/opt/tplink/EAPController/properties/${BASENAME}"
  fi
done

# set default time zone and notify user of time zone
bashio::log.info "Time zone set to '${TZ}'"

# append smallfiles if set to true
if [ "${SMALL_FILES}" = "true" ]
then
  echo "WARN: smallfiles was passed but is not supported in >= 4.1 with the WiredTiger engine in use by MongoDB"
  bashio::log.info "Skipping setting smallfiles option"
fi

# update stored ports when different of enviroment defined ports (works for numbers only)
for ELEM in MANAGE_HTTP_PORT MANAGE_HTTPS_PORT PORTAL_HTTP_PORT PORTAL_HTTPS_PORT PORT_ADOPT_V1 PORT_APP_DISCOVERY PORT_UPGRADE_V1 PORT_MANAGER_V1 PORT_MANAGER_V2 PORT_DISCOVERY PORT_TRANSFER_V2 PORT_RTTY
do
  # convert element to key name
  KEY="$(echo "${ELEM}" | tr '[:upper:]' '[:lower:]' | tr '_' '.')"

  # get value we want to set from the element
  END_VAL=${!ELEM}

  # get the current value from the omada.properties file
  STORED_PROP_VAL=$(grep -Po "(?<=${KEY}=)([0-9]+)" /opt/tplink/EAPController/properties/omada.properties || true)

  # check to see if we need to set the value
  if [ "${STORED_PROP_VAL}" = "" ]
  then
    bashio::log.info "Skipping '${KEY}' - not present in omada.properties"
  elif [ "${STORED_PROP_VAL}" != "${END_VAL}" ]
  then
    # check to see if we are trying to bind to privileged port
    if [ "${END_VAL}" -lt "1024" ] && [ "$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start)" = "1024" ]
    then
      bashio::log.error "Unable to set '${KEY}' to ${END_VAL}; 'ip_unprivileged_port_start' has not been set.  See https://github.com/mbentley/docker-omada-controller#unprivileged-ports"
      exit 1
    fi

    # update the key-value pair
    bashio::log.info "Setting '${KEY}' to ${END_VAL} in omada.properties"
    sed -i "s~^${KEY}=${STORED_PROP_VAL}$~${KEY}=${END_VAL}~g" /opt/tplink/EAPController/properties/omada.properties
  else
    # values already match; nothing to change
    bashio::log.info "Value of '${KEY}' already set to ${END_VAL} in omada.properties"
  fi
done

# update stored property values when different of environment defined values (works for any value)
for ELEM in MONGO_EXTERNAL EAP_MONGOD_URI
do
  # convert element to key name
  KEY="$(echo "${ELEM}" | tr '[:upper:]' '[:lower:]' | tr '_' '.')"

  # get the full key & value to store for checking later
  KEY_VALUE="$(grep "^${KEY}=" /opt/tplink/EAPController/properties/omada.properties || true)"

  # get value we want to set from the element
  END_VAL=${!ELEM}

  # get the current value from the omada.properties file
  STORED_PROP_VAL=$(grep -Po "(?<=${KEY}=)(.*)+" /opt/tplink/EAPController/properties/omada.properties || true)

  # check to see if we need to set the value; see if there is something in the key/value first
  if [ -z "${KEY_VALUE}" ]
  then
    bashio::log.info "Skipping '${KEY}' - not present in omada.properties"
  elif [ "${STORED_PROP_VAL}" != "${END_VAL}" ]
  then
    # update the key-value pair
    bashio::log.info "Setting '${KEY}' to ${END_VAL} in omada.properties"
    sed -i "s~^${KEY}=${STORED_PROP_VAL}$~${KEY}=${END_VAL}~g" /opt/tplink/EAPController/properties/omada.properties
  else
    # values already match; nothing to change
    bashio::log.info "Value of '${KEY}' already set to ${END_VAL} in omada.properties"
  fi
done

# make sure that the html directory exists
if [ ! -d "/opt/tplink/EAPController/data/html" ] && [ -f "/opt/tplink/EAPController/data-html.tar.gz" ]
then
  # missing directory; extract from original
  bashio::log.info "Report HTML directory missing; extracting backup to '/opt/tplink/EAPController/data/html'"
  tar zxvf /opt/tplink/EAPController/data-html.tar.gz -C /opt/tplink/EAPController/data
  chown -R "${PUSERNAME}:${PGROUP}" /opt/tplink/EAPController/data/html
fi

# make sure that the pdf directory exists
if [ ! -d "/opt/tplink/EAPController/data/pdf" ]
then
  # missing directory; extract from original
  bashio::log.info "Report PDF directory missing; creating '/opt/tplink/EAPController/data/pdf'"
  mkdir /opt/tplink/EAPController/data/pdf
  chown -R "${PUSERNAME}:${PGROUP}" /opt/tplink/EAPController/data/pdf
fi

# make sure permissions are set appropriately on each directory
for DIR in data logs properties
do
  OWNER="$(stat -c '%u' /opt/tplink/EAPController/${DIR})"
  GROUP="$(stat -c '%g' /opt/tplink/EAPController/${DIR})"

  if [ "${OWNER}" != "${PUID}" ] || [ "${GROUP}" != "${PGID}" ]
  then
    # notify user that uid:gid are not correct and fix them
    echo "WARN: Ownership not set correctly on '/opt/tplink/EAPController/${DIR}'; setting correct ownership (${PUSERNAME}:${PGROUP})"
    chown -R "${PUSERNAME}:${PGROUP}" "/opt/tplink/EAPController/${DIR}"
  fi
done

# validate permissions on /tmp
TMP_PERMISSIONS="$(stat -c '%a' /tmp)"
if [ "${TMP_PERMISSIONS}" != "1777" ]
then
  echo "WARN: Permissions are not set correctly on '/tmp' (${TMP_PERMISSIONS}); setting correct permissions (1777)"
  chmod -v 1777 /tmp
fi

# check to see if there is a db directory; create it if it is missing
if [ ! -d "/opt/tplink/EAPController/data/db" ]
then
  bashio::log.info "Database directory missing; creating '/opt/tplink/EAPController/data/db'"
  mkdir /opt/tplink/EAPController/data/db
  chown "${PUSERNAME}:${PGROUP}" /opt/tplink/EAPController/data/db
  echo "done"
fi

# Import a cert from a possibly mounted secret or file at /cert
if [ -f "/cert/${SSL_KEY_NAME}" ] && [ -f "/cert/${SSL_CERT_NAME}" ]
then
  # see where the keystore directory is; check for old location first
  if [ -d /opt/tplink/EAPController/keystore ]
  then
    # keystore in the parent folder before 5.3.1
    KEYSTORE_DIR="/opt/tplink/EAPController/keystore"
  else
    # keystore directory moved to the data directory in 5.3.1
    KEYSTORE_DIR="/opt/tplink/EAPController/data/keystore"

    # check to see if the KEYSTORE_DIR exists (it won't on upgrade)
    if [ ! -d "${KEYSTORE_DIR}" ]
    then
      bashio::log.info "Creating keystore directory (${KEYSTORE_DIR})"
      mkdir "${KEYSTORE_DIR}"
      bashio::log.info "Setting permissions on ${KEYSTORE_DIR}"
      chown "${PUSERNAME}:${PGROUP}" "${KEYSTORE_DIR}"
    fi
  fi

  bashio::log.info "Importing cert from /cert/tls.[key|crt]"
  # delete the existing keystore
  rm -f "${KEYSTORE_DIR}/eap.keystore"

  # example certbot usage: ./certbot-auto certonly --standalone --preferred-challenges http -d mydomain.net
  openssl pkcs12 -export \
    -inkey "/cert/${SSL_KEY_NAME}" \
    -in "/cert/${SSL_CERT_NAME}" \
    -certfile "/cert/${SSL_CERT_NAME}" \
    -name eap \
    -out "${KEYSTORE_DIR}/eap.keystore" \
    -passout pass:tplink

  # set ownership/permission on keystore
  chown "${PUSERNAME}:${PGROUP}" "${KEYSTORE_DIR}/eap.keystore"
  chmod 400 "${KEYSTORE_DIR}/eap.keystore"
fi

# re-enable disabled TLS versions 1.0 & 1.1
if [ "${TLS_1_11_ENABLED}" = "true" ]
then
  bashio::log.info "Re-enabling TLS 1.0 & 1.1"
  if [ -f "/etc/java-8-openjdk/security/java.security" ]
  then
    # openjdk8
    sed -i 's#^jdk.tls.disabledAlgorithms=SSLv3, TLSv1, TLSv1.1,#jdk.tls.disabledAlgorithms=SSLv3,#' /etc/java-8-openjdk/security/java.security
  elif [ -f "/etc/java-17-openjdk/security/java.security" ]
  then
    # openjdk17
    sed -i 's#^jdk.tls.disabledAlgorithms=SSLv3, TLSv1, TLSv1.1,#jdk.tls.disabledAlgorithms=SSLv3,#' /etc/java-17-openjdk/security/java.security
  else
    # not running openjdk8 or openjdk17
    echo "WARN: Unable to re-enable TLS 1.0 & 1.1; unable to detect openjdk version"
  fi
fi

# see if any of these files exist; if so, do not start as they are from older versions
if [ -f /opt/tplink/EAPController/data/db/tpeap.0 ] || [ -f /opt/tplink/EAPController/data/db/tpeap.1 ] || [ -f /opt/tplink/EAPController/data/db/tpeap.ns ]
then
  bashio::log.error "The data volume mounted to /opt/tplink/EAPController/data appears to have data from a previous version!"
  echo "  Follow the upgrade instructions at https://github.com/mbentley/docker-omada-controller#upgrading-to-41"
  exit 1
fi

# check to see if the CMD passed contains the text "com.tplink.omada.start.OmadaLinuxMain" which is the old classpath from 4.x
if [ "$(echo "${@}" | grep -q "com.tplink.omada.start.OmadaLinuxMain"; echo $?)" = "0" ]
then
  echo -e "\n############################"
  bashio::log.warning "CMD from 4.x detected!  It is likely that this container will fail to start properly with a \"Could not find or load main class com.tplink.omada.start.OmadaLinuxMain\" error!"
  echo "  See the note on old CMDs at https://github.com/mbentley/docker-omada-controller/blob/master/KNOWN_ISSUES.md#upgrade-issues for details on why and how to resolve the issue."
  echo -e "############################\n"
fi

# compare version from the image to the version stored in the persistent data (last ran version)
if [ -f "/opt/tplink/EAPController/IMAGE_OMADA_VER.txt" ]
then
  # file found; read the version that is in the image
  IMAGE_OMADA_VER="$(cat /opt/tplink/EAPController/IMAGE_OMADA_VER.txt)"
else
  bashio::log.error "Missing image version file (/opt/tplink/EAPController/IMAGE_OMADA_VER.txt); this should never happen!"
  exit 1
fi

# load LAST_RAN_OMADA_VER, if file present
if [ -f "/opt/tplink/EAPController/data/LAST_RAN_OMADA_VER.txt" ]
then
  # file found; read the version that was last recorded
  LAST_RAN_OMADA_VER="$(cat /opt/tplink/EAPController/data/LAST_RAN_OMADA_VER.txt)"
else
  # no file found; set version to 0.0.0 as we don't know the last version
  LAST_RAN_OMADA_VER="0.0.0"
fi

# use sort to check which version is newer; should sort the newest version to the top
if [ "$(printf '%s\n' "${IMAGE_OMADA_VER}" "${LAST_RAN_OMADA_VER}" | sort -rV | head -n1)" != "${IMAGE_OMADA_VER}" ]
then
  # version in the image is didn't match newest image version; this means we are trying to start and older version
  bashio::log.error "The version from the image (${IMAGE_OMADA_VER}) is older than the last version executed (${LAST_RAN_OMADA_VER})!  Refusing to start to prevent data loss!"
  echo "  To bypass this check, remove /opt/tplink/EAPController/data/LAST_RAN_OMADA_VER.txt only if you REALLY know what you're doing!"
  exit 1
else
  bashio::log.info "Version check passed; image version (${IMAGE_OMADA_VER}) >= the last version ran (${LAST_RAN_OMADA_VER}); writing image version to last ran file..."
  echo "${IMAGE_OMADA_VER}" > /opt/tplink/EAPController/data/LAST_RAN_OMADA_VER.txt
fi

# check to see if we are in a bad situation with a 32 bit userland and 64 bit kernel (fails to start MongoDB on a Raspberry Pi)
if [ "$(dpkg --print-architecture)" = "armhf" ] && [ "$(uname -m)" = "aarch64" ] && [ "${SKIP_USERLAND_KERNEL_CHECK}" = "false" ]
then
  echo "##############################################################################"
  echo "##############################################################################"
  bashio::log.error "32 bit userspace with 64 bit kernel detected!  MongoDB will NOT start!"
  echo "  See https://github.com/mbentley/docker-omada-controller/blob/master/KNOWN_ISSUES.md#mismatched-userland-and-kernel for how to fix the issue"
  echo "##############################################################################"
  echo "##############################################################################"

  exit 1
else
  bashio::log.info "userland/kernel check passed"
fi

# show java version
echo -e "INFO: output of 'java -version':\n$(java -version 2>&1)\n"

# get the java version in different formats
JAVA_VERSION="$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}')"
JAVA_VERSION_1="$(echo "${JAVA_VERSION}" | awk -F '.' '{print $1}')"
JAVA_VERSION_2="$(echo "${JAVA_VERSION}" | awk -F '.' '{print $2}')"

# for java 8, remove the opens argument from the CMD
case ${JAVA_VERSION_1}.${JAVA_VERSION_2} in
  1.8)
    bashio::log.info "running Java 8; removing '--add-opens' option(s) from CMD (if present)..."
    # remove opens option
    NEW_CMD="${*}"
    NEW_CMD="${NEW_CMD/'--add-opens java.base/sun.security.x509=ALL-UNNAMED '/}"
    NEW_CMD="${NEW_CMD/'--add-opens java.base/sun.security.util=ALL-UNNAMED '/}"
    # shellcheck disable=SC2086
    set -- ${NEW_CMD}
    ;;
esac

# check for autobackup
if [ ! -d "/opt/tplink/EAPController/data/autobackup" ]
then
  echo
  echo "##############################################################################"
  echo "##############################################################################"
  echo "WARNGING: autobackup directory not found! Please configure automatic backups!"
  echo "  For instructions, see https://github.com/mbentley/docker-omada-controller#controller-backups"
  echo "##############################################################################"
  echo "##############################################################################"
  echo
  sleep 2
fi

bashio::log.info "Starting Omada Controller as user ${PUSERNAME}"

# tail the omada logs if set to true
if [ "${SHOW_SERVER_LOGS}" = "true" ]
then
  gosu "${PUSERNAME}" tail -F -n 0 /opt/tplink/EAPController/logs/server.log &
fi

# tail the mongodb logs if set to true
if [ "${SHOW_MONGODB_LOGS}" = "true" ]
then
  gosu "${PUSERNAME}" tail -F -n 0 /opt/tplink/EAPController/logs/mongod.log &
fi

# run the actual command as the omada user
exec gosu "${PUSERNAME}" "${@}"