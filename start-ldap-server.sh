#!/bin/bash

set -e

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 corp user1 user2 ..." >&2
  echo "  Sets up an LDAP server with specified users." >&2
  echo "" >&2
  echo "Example: $0 mycorp john jill" >&2
  echo "  will setup john and jill as users with passwords john_pass and jill_pass, with dc=mycorp,dc=com" >&2
  exit 1
fi

CORP=$1
shift
USERS=("$@")

CONTAINER_NAME=${CONTAINER_NAME:-test_ldap_server}
docker stop $CONTAINER_NAME || true
docker rm $CONTAINER_NAME || true
LDAP_PORT=${LDAP_PORT:-389}

# The container nickstenning/slapd had the issue specified in https://github.com/docker/docker/issues/8231. I add a line
# just before the last one here (https://github.com/nickstenning/docker-slapd/blob/master/slapd.sh) and made it do a
# ulimit -n 1024.  That fixed the memory usage and I could run multiple LDAP servers.
# CONTAINER=$(docker run -e LDAP_DOMAIN="${CORP}.com" -e LDAP_ORGANISATION="Corp_${CORP}" -e LDAP_ROOTPASS=secret -P -d nickstenning/slapd)
CONTAINER=$(docker run -e LDAP_DOMAIN="${CORP}.com" -e LDAP_ORGANISATION="Corp_${CORP}" -e LDAP_ROOTPASS=secret -P -p $LDAP_PORT:$LDAP_PORT --name $CONTAINER_NAME -d arvindsv/slapd)

# To check whether the above has been fixed, and you can use nickstenning/slapd, just start this container and check memory usage using:
# boot2docker ssh free -m
# If you see it lose 800MB or so after this container starts, you have a problem. If not, it's fixed.

if [[ "$OSTYPE" == "darwin"* ]]; then
	LDAP_HOST=$(docker-machine ip default)
else
	LDAP_HOST=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' ${CONTAINER_NAME})
fi

cat >data.ldif <<EOF
dn: ou=People,dc=$CORP,dc=com
objectClass: organizationalUnit
ou: People

dn: ou=Groups,dc=$CORP,dc=com
objectClass: organizationalUnit
ou: Groups

dn: cn=miners,ou=Groups,dc=$CORP,dc=com
objectClass: posixGroup
cn: miners
gidNumber: 5000

EOF

count=0
for user in "${USERS[@]}"; do
  echo "Adding user $user to config."

  cat >>data.ldif <<EOF
dn: uid=$user,ou=People,dc=$CORP,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: $user
sn: LastName_$user
givenName: User_$user
cn: User_$user LastName_$user
displayName: User_$user LastName_$user
uidNumber: $((10000 + count))
gidNumber: 5000
userPassword: pass_${user}
gecos: User_$user LastName_$user
loginShell: /bin/bash
homeDirectory: /home/$user

EOF
  count=$((count + 1))
done

echo "Wait for LDAP server to start ... - 3 seconds"; sleep 3

ldapadd -h $LDAP_HOST -p $LDAP_PORT -x -c -D cn=admin,dc=$CORP,dc=com -w secret -f data.ldif

echo "LDAP info:"
echo "  URI: ldap://$LDAP_HOST:$LDAP_PORT"
echo "  Search base: ou=People,dc=$CORP,dc=com"
echo "  Search filter: (uid={0})"
echo
for user in "${USERS[@]}"; do
  echo "User: $user. Password: pass_${user}"
done
