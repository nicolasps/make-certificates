MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -e -u -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:

define printColor
	echo -e "${$1}${2}${NO_COLOR}"
endef

export RED                                        :=\033[0;31m
export GREEN                                      :=\033[0;32m
export YELLOW                                     :=\033[0;33m
export BLUE                                       :=\033[0;34m
export PURPLE                                     :=\033[0;35m
export NO_COLOR                                   :=\033[0m

export TEMP_FOLDER                                := ./_temp
export OUTPUT_FOLDER                              := output
export RESOURCES_FOLDER                           := ./resources
export CA_PRIVATE_KEY                             := $(OUTPUT_FOLDER)/ca.pk
export CA_CERTIFICATE                             := $(OUTPUT_FOLDER)/ca.pem
export CA_SUBJECT                                 := enter-your-domain.here.com
export EXPIRATION_DAYS                            := 365
export CERTIFICATE_CLIENT_REQUEST                 := $(OUTPUT_FOLDER)/client.csr
export CERTIFICATE_CLIENT_PRIVATE_KEY             := $(OUTPUT_FOLDER)/client.pk
export CERTIFICATE_CLIENT_SIGNED_CERTIFICATE      := ${OUTPUT_FOLDER}/client.pem
export CERTIFICATE_CLIENT_DOMAIN                  := enter-your-domain.here.com

.PHONY: all
all:
	@echo "Possible Targets:"
	@less Makefile | grep .PHONY[:] | cut -f2 -d ' ' | xargs -n1 -r echo " - "

remove-temp-folder:
	@-rm -rf $(TEMP_FOLDER)

create-working-folders:
	@mkdir -p $(TEMP_FOLDER) && sleep 1
	@mkdir -p $(OUTPUT_FOLDER)

avoid-ca-deletion:
	@if [[ -f $(CA_PRIVATE_KEY) ]]; then \
		while [ -z "$${CONTINUE:-}" ]; do \
			read -r -p "WARNING: You are about to delete the existig CA. Are you sure ?  [y/n]: " CONTINUE; \
		done; [ $$CONTINUE = "y" ] || [ $$CONTINUE = "Y" ] || (echo "CA creation Aborted!"; exit 1;) \
	fi;

.PHONY: create-ca
create-ca: create-working-folders avoid-ca-deletion
	@$(call printColor,PURPLE,"-- Creating a certificate-authority - CA ")
	@cat settings/openssl-ca.cnf | envsubst > $(TEMP_FOLDER)/openssl-ca.cnf-generated
	@sudo openssl req -x509 -config $(TEMP_FOLDER)/openssl-ca.cnf-generated \
		-newkey rsa:4096  -sha256 -nodes \
		-outform PEM \
		-out $(CA_CERTIFICATE) \
		-keyout $(CA_PRIVATE_KEY) \
		-days $(EXPIRATION_DAYS) \
		-subj "/CN=$(CA_SUBJECT)";
	@$(call printColor,PURPLE,"-- Finished: certificate-authority - CA")
	@openssl x509 -in $(CA_CERTIFICATE) -text -noout | head -n 14 | grep --color -Ei "Issuer:|Subject:|\$$"
	@-rm -rf $(TEMP_FOLDER)/openssl-ca.cnf-generated 2> /dev/null

.PHONY: create-csr-and-pk
create-csr-and-pk: remove-temp-folder create-working-folders
	@$(call printColor,PURPLE,"-- Creating a certificate request ")
	@cat settings/openssl-server.cnf | envsubst > $(TEMP_FOLDER)/openssl-server.cnf-generated
	@openssl req -config $(TEMP_FOLDER)/openssl-server.cnf-generated \
		-newkey rsa:4096  \
		-sha256 \
		-nodes \
		-outform PEM \
		-out $(CERTIFICATE_CLIENT_REQUEST) \
		-keyout $(CERTIFICATE_CLIENT_PRIVATE_KEY) \
		-subj "/CN=*.$(CERTIFICATE_CLIENT_DOMAIN)/O=$(CERTIFICATE_CLIENT_DOMAIN)";
	@$(call printColor,PURPLE,"-- Finished: certificate request ")
	@-rm -v $(TEMP_FOLDER)/openssl-server.cnf-generated
	@openssl req -in $(CERTIFICATE_CLIENT_REQUEST) -text -noout | head -n 37  | grep --color -E "Issuer:|Subject:|CA:|Alternative Name|\$$"

.PHONY: sign-csr
sign-csr: remove-temp-folder create-working-folders
	@$(call printColor,PURPLE,"-- Signing the CSR: $(CERTIFICATE_CLIENT_REQUEST)")
	@sleep 2
	@touch $(TEMP_FOLDER)/db
	@echo "$$(date +%s)" > $(TEMP_FOLDER)/serial
	@cat settings/openssl-ca.cnf | envsubst > $(TEMP_FOLDER)/openssl-ca.cnf-generated
	@sudo openssl ca -config $(TEMP_FOLDER)/openssl-ca.cnf-generated \
		-policy signing_policy \
		-extensions signing_req \
		-create_serial \
		-rand_serial \
		-days $(EXPIRATION_DAYS) \
		-outdir $(TEMP_FOLDER) \
		-cert $(CA_CERTIFICATE) \
		-keyfile $(CA_PRIVATE_KEY) \
		-out $(CERTIFICATE_CLIENT_SIGNED_CERTIFICATE) \
		-batch \
		-notext \
		-infiles $(CERTIFICATE_CLIENT_REQUEST);
	@$(call printColor,PURPLE,"-- Finished. A signed certificate was created at: $(CERTIFICATE_CLIENT_SIGNED_CERTIFICATE)")
	@-rm -rf $(TEMP_FOLDER)/openssl-ca.cnf-generated 2> /dev/null

convert-pem-to-crt:
	@openssl x509 -outform der -in $(CA_CERTIFICATE) -out $(CA_CERTIFICATE_CRT)
