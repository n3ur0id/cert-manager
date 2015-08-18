#!/bin/sh

# Initialize variables
PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin



_read_ca_config () {
	sed '1d;$d' ${KEY_DIR}/${VPN_SERVER}/ca.config |
	sed "s/[>,']//g"  
}

init_vars () {
	set -o allexport
	[ -s /usr/local/etc/cert-manager.rc ] && . /usr/local/etc/cert-manager.rc
	[ -s "${0%/*}/cert-manager.rc" ] && . ${0%/*}/cert-manager.rc 
	[ -s ${KEY_DIR}/${VPN_SERVER}/ca.config ] && export $(_read_ca_config)
	set +o allexport
	export KEY_CN=${KEY_NAME}
	export KEY_DIR=${KEY_DIR}/${VPN_SERVER}
	export KEY_CLIENT_DIR=${KEY_CLIENT_DIR}/${VPN_SERVER}
}

new_cert () {
	[ -z "$CM_SILENT_MODE" ] && echo "===>>> New cert "
	[ -f  ${KEY_DIR}/${KEY_NAME}.crt ] && echo "===>>> Error: key exists ${KEY_DIR}/${KEY_NAME}.crt " && exit 0

	openssl req -new -batch -days ${KEY_EXPIRE} \
		-keyout ${KEY_DIR}/${KEY_NAME}.key -out ${KEY_DIR}/${KEY_NAME}.csr \
		-nodes -config ${KEY_CONFIG} > /dev/null 2>&1

	openssl ca -batch -days ${CA_EXPIRE}  -out ${KEY_DIR}/${KEY_NAME}.crt \
		-in ${KEY_DIR}/${KEY_NAME}.csr -config ${KEY_CONFIG} > /dev/null 2>&1

	chmod 0600 ${KEY_DIR}/${KEY_NAME}.* 
}

revoke_cert () {
	[ -z "$CM_SILENT_MODE" ] && echo "===>>> Revoke cert "
	[ ! -f  ${KEY_DIR}/${KEY_NAME}.crt ] && echo "===>>> Error: key does not exists ${KEY_DIR}/${KEY_NAME}.crt " && exit 0
	local revoke_chk
	openssl ca -revoke ${KEY_DIR}/${KEY_NAME}.crt -config ${KEY_CONFIG} > /dev/null 2>&1
	openssl ca -gencrl -out ${KEY_DIR}/crl.pem -config  ${KEY_CONFIG} > /dev/null 2>&1
	cat ${KEY_DIR}/ca.crt ${KEY_DIR}/crl.pem > ${KEY_DIR}/revoke-test.pem
#	openssl verify -CAfile ${KEY_DIR}/revoke-test.pem -crl_check ${KEY_DIR}/${KEY_NAME}.crt > /dev/null 2>&1 
	openssl verify -CAfile ${KEY_DIR}/revoke-test.pem -crl_check ${KEY_DIR}/${KEY_NAME}.crt > /dev/null 2>&1  
#echo "Note the "error 23" in the last line. That is what you want to see,"
#echo "as it indicates that a certificate verification of the revoked certificate failed"
	rm -f ${KEY_DIR}/${KEY_NAME}.*
	rm -f ${KEY_CLIENT_DIR}/${KEY_NAME}/*
	[ -d  ${KEY_CLIENT_DIR}/${KEY_NAME} ] && rmdir ${KEY_CLIENT_DIR}/${KEY_NAME}
	[ -z "$CM_SILENT_MODE" ] && echo "===>>> Remove client conf "
}

send_cert () {
	[ -z "$CM_SILENT_MODE" ] && echo "===>>> Send cert "
}

version () {
	echo '' ; echo "===>>> Version 0.1 "
}

client_config () {
	local cfg_remote cfg_port cfg_cipher
	[ -z "$CM_SILENT_MODE" ] && echo "===>>> Client config "
	[ ! -d  ${KEY_CLIENT_DIR}/${KEY_NAME} ] && mkdir -p ${KEY_CLIENT_DIR}/${KEY_NAME}
	cp -a ${KEY_DIR}/${KEY_NAME}.crt ${KEY_CLIENT_DIR}/${KEY_NAME}/${KEY_NAME}.crt
	cp -a ${KEY_DIR}/${KEY_NAME}.key ${KEY_CLIENT_DIR}/${KEY_NAME}/${KEY_NAME}.key
	cp -a ${KEY_DIR}/ca.crt  ${KEY_CLIENT_DIR}/${KEY_NAME}/ca.crt
	cp -a ${KEY_DIR}/dh${KEY_SIZE}.pem  ${KEY_CLIENT_DIR}/${KEY_NAME}/dh${KEY_SIZE}.pem

	[ ! -f ${OVPN_DIR}/${VPN_SERVER}.conf ] && echo "===>>> Error: file ${OVPN_DIR}/${VPN_SERVER}.conf does not exists" && exit 0
	[ -z "$cfg_remote"] && cfg_remote=`sed -n 's/^local[ ]*\(.*\)$/\1/p' ${OVPN_DIR}/${VPN_SERVER}.conf `
	[ -z "$cfg_port"] && cfg_port=`sed -n 's/^port[ ]*\(.*\)$/\1/p' ${OVPN_DIR}/${VPN_SERVER}.conf `
	[ -z "$cfg_cipher"] && cfg_cipher=`sed -n 's/^cipher[ ]*\(.*\)$/\1/p' ${OVPN_DIR}/${VPN_SERVER}.conf `

	cat > ${KEY_CLIENT_DIR}/${KEY_NAME}/${KEY_NAME}.conf <<_EOF_
client
proto tcp-client
dev tun
ca ca.crt
dh dh1024.pem
cert ${KEY_NAME}.crt
key ${KEY_NAME}.key
remote ${cfg_remote} ${cfg_port}
cipher ${cfg_cipher}
user nobody
group nogroup
verb 2
mute 20
keepalive 10 120
comp-lzo
persist-key
persist-tun
float
resolv-retry infinite
nobind
_EOF_

#	gsed 's/$/\r/g' ${KEY_CLIENT_DIR}/${KEY_NAME}/${KEY_NAME}.conf > ${KEY_CLIENT_DIR}/${KEY_NAME}/${KEY_NAME}.ovpn
	sed 's/$//g' ${KEY_CLIENT_DIR}/${KEY_NAME}/${KEY_NAME}.conf > ${KEY_CLIENT_DIR}/${KEY_NAME}/${KEY_NAME}.ovpn
}


usage () {

	version
	echo ''
	echo 'Usage:'
	echo "Common flags: [--new] | [--revoke] | [--send] | [--silent]"
	echo "${0##*/} [Common flags] <VPN_SERVER=srvname> <KEY_NAME=keyname>"
	echo ''
	echo "${0##*/} --help"
	echo "${0##*/} --version"
	echo ''
	exit ${1:-0}
}

for var in "$@" ; do
	case "$var" in
	-[A-Za-z0-9]*)		newopts="$newopts $var" ;;
	--new)			CM_NEW_CERT=cm_new_cert
				export CM_NEW_CERT ;;
	--revoke)		CM_REVOKE_CERT=cm_revoke_cert
				export CM_REVOKE_CERT ;;
	--send)			CM_SEND_CERT=cm_send_cert
				export CM_SEND_CERT ;;
	--silent)		CM_SILENT_MODE=cm_silent_mode
				export CM_SILENT_MODE ;;
	--help)			usage 0 ;;
	--version)		version ; exit 0 ;;
	--*)			echo "Illegal option $var" ; echo ''
				echo "===>>> Try ${0##*/} --help"; exit 1 ;;
	*)			newopts="$newopts $var" ;;
	esac
done

[ -z "$newopts" ] && usage

set -- $newopts
[ -n "$newopts" ] && export $newopts
unset var newopts

[ -z "$KEY_NAME" ] || [ -z "$VPN_SERVER" ]   && usage ;

[ -n "$KEY_NAME" ] && [ -n "$VPN_SERVER" ]  && init_vars ;

#[ -n "$CM_NEW_CERT" ] && [ -n "$CM_SEND_CERT" ] && new_cert && send_cert ; exit 0;
[ -n "$CM_NEW_CERT" ] && new_cert && client_config; 

[ -n "$CM_REVOKE_CERT" ] && revoke_cert ; 

[ -n "$CM_SEND_CERT" ] && send_cert ; 

