MAKEFLAGS += --silent

RPM_NAME	?= $(if $(strip $(NAME)),$(NAME),default)
RPM_CHANGELOG	?= rpm/changelog
RPM_LASTVER	?= $(shell head -1 $(RPM_CHANGELOG) | grep -Po '\S+$$')
RPM_VERSION	?= $(if $(strip $(VERSION)),$(VERSION),$(firstword $(subst -, ,$(RPM_LASTVER))))
RPM_RELEASE	?= $(if $(strip $(RELEASE)),$(RELEASE),$(lastword $(subst -, ,$(RPM_LASTVER))))
RPM_ARCH	?= $(if $(strip $(ARCH)),$(shell arch))
RPM_SPECS_IN	?= $(wildcard rpm/*spec.in)
RPM_PACKAGER	?= $(if $(strip $(PACKAGER)),$(PACKAGER),$(shell getent passwd `whoami` | cut -d ':' -f 5) <$(shell whoami)@$(shell hostname -f)>)
RPM_VENDOR	?= $(if $(strip $(VENDOR)),$(VENDOR),nobody)
RPM_TARGET_DIR	?= $(if $(strip $(TARGET_DIR)),$(TARGET_DIR),$(abspath target))
RPM_BUILD_DIR	?= $(if $(strip $(BUILD_DIR)),$(BUILD_DIR),$(RPM_TARGET_DIR)/build)
RPM_DISTS_DIR	?= $(if $(strip $(DISTS_DIR)),$(DISTS_DIR),$(RPM_TARGET_DIR)/dists)
RPM_WORKS_DIR	?= $(if $(strip $(WORKS_DIR)),$(WORKS_DIR),$(RPM_TARGET_DIR)/works)
RPM_DEBUGINFO	?= 0
LOG_FILE	?= $(RPM_NAME).log

rpm_sedsrcs = sed -n -r -e "s/^\s*Source[0-9]*:\s*(https?|ftp)(:.+)/\1\2/ p"
rpm_sedsubs	= sed -e "s/\#RPM_NAME\#/$(RPM_NAME)/g"
rpm_sedsubs	+=    -e "s/\#RPM_VERSION\#/$(RPM_VERSION)/g"
rpm_sedsubs	+=    -e "s/\#RPM_RELEASE\#/$(RPM_RELEASE)/g"
rpm_sedsubs	+=    -e "s/\#RPM_ARCH\#/$(RPM_ARCH)/g"
rpm_sedsubs	+=    -e "s/\#RPM_PACKAGER\#/$(RPM_PACKAGER)/g"
rpm_sedsubs	+=    -e "s/\#RPM_PACKAGER\#/$(RPM_VENDOR)/g"

.PHONY: rpm rpm_check rpm_pre rpm_src rpm_specs rpm_deps rpm_build rpm_post

rpm: rpm_pre rpm_src rpm_specs rpm_deps rpm_build rpm_post

rpm_check: RPM_SPECS		?= $(RPM_SPECS_IN)
rpm_check: REMOTE_SOURCES	?= $(shell $(rpm_sedsrcs) $(RPM_SPECS) | $(rpm_sedsubs))
rpm_check:
	echo -n "RPM - Spec file ($(RPM_SPECS))... "
	{ $(foreach RPM_SPEC,$(RPM_SPECS), \
		test -f "$(RPM_SPEC)"; \
	)} && echo "present" \
	|| { echo "missing"; exit 1; };
	echo -n "RPM - Changelog file ($(RPM_CHANGELOG))... "
	test -f "$(RPM_CHANGELOG)" && echo "present" \
	|| { echo "missing"; exit 1; };
	$(foreach SOURCE,$(REMOTE_SOURCES), \
		echo -n "RPM - Source file ($(notdir $(SOURCE)))... "; \
		test -f "$(RPM_BUILD_DIR)/SOURCES/$(notdir $(SOURCE))" \
		&& echo "present" \
		|| { echo "remote"; \
			curl --silent --show-error --head --location --url "$(SOURCE)" --output /dev/null \
			|| exit 1; \
		}; \
	)

rpm_pre:
	# Empty log file first
	echo `date` - rpm_pre >> "$(LOG_FILE)"
	echo -n "RPM - Creating build and dist directories... ";
	mkdir -vp \
		"$(RPM_BUILD_DIR)/RPMS" \
		"$(RPM_BUILD_DIR)/SOURCES" \
		"$(RPM_BUILD_DIR)/BUILD" \
		"$(RPM_BUILD_DIR)/BUILDROOT" \
		"$(RPM_BUILD_DIR)/SPECS" \
		"$(RPM_BUILD_DIR)/SRPMS" \
		"$(RPM_DISTS_DIR)" \
		>> "$(LOG_FILE)" 2>&1 \
		|| { echo "failed (see "$(LOG_FILE)")"; exit 1; };
	echo "ok"

rpm_src: RPM_SPECS		?= $(RPM_SPECS_IN)
rpm_src: REMOTE_SOURCES	?= $(shell $(rpm_sedsrcs) $(RPM_SPECS) | $(rpm_sedsubs))
rpm_src: LOCAL_SOURCES	?= $(wildcard src/*)
rpm_src: rpm_specs
	echo `date` - rpm_src >> "$(LOG_FILE)"
	echo -n "RPM - Downloading remotes sources if needed... ";
	$(foreach SOURCE,$(REMOTE_SOURCES), test -f "$(RPM_BUILD_DIR)/SOURCES/$(notdir $(SOURCE))" \
		|| curl --silent --show-error --location --url "$(SOURCE)" --output "$(RPM_BUILD_DIR)/SOURCES/$(notdir $(SOURCE))" 2>> "$(LOG_FILE)" \
		|| { echo "failed for $(SOURCE) (see "$(LOG_FILE)")"; exit 1;}; \
	)
	echo "ok";

	echo -n "RPM - Creating links to local sources if needed... ";
	$(foreach SOURCE,$(LOCAL_SOURCES), test -L "$(RPM_BUILD_DIR)/SOURCES/$(notdir $(SOURCE))" \
		|| ln --verbose --force --symbolic --target-directory="$(RPM_BUILD_DIR)/SOURCES" "$(abspath $(SOURCE))" >> "$(LOG_FILE)" 2>&1 \
		|| { echo "failed for $(SOURCE) (see "$(LOG_FILE)")"; exit 1;}; \
	)
	echo "ok";

rpm_specs: RPM_SPECS		?= $(RPM_SPECS_IN)
rpm_specs: RPM_CHANGELOG	?= rpm/changelog
rpm_specs:
	echo `date` - rpm_specs >> "$(LOG_FILE)"
	echo -n "RPM - Preparing changelog for the template spec file... ";
	test -f "$(word 1,$(RPM_SPECS))" -a -f "$(RPM_CHANGELOG)" || { echo "failed (see "$(LOG_FILE)")"; exit 1; };
	cat "$(RPM_CHANGELOG)" > "$(RPM_BUILD_DIR)/SPECS/changelog" 2>> "$(LOG_FILE)" || { echo "failed (see "$(LOG_FILE)")"; exit 1; };
	echo "ok";
	echo -n "RPM - Generating the spec file from template... ";
	$(foreach RPM_SPEC,$(RPM_SPECS), \
		cat "$(RPM_SPEC)" | $(rpm_sedsubs) \
		> "$(RPM_BUILD_DIR)/SPECS/$(RPM_NAME)-$(subst .,-,$(patsubst rpm/%spec.in,%,$(RPM_SPEC)))$(RPM_VERSION).spec" \
		2>> "$(LOG_FILE)" || { echo "failed (see "$(LOG_FILE)")"; exit 1; }; \
	)
	echo "ok";

rpm_deps: RPM_SPECS		?= $(wildcard $(RPM_BUILD_DIR)/SPECS/*-$(RPM_VERSION).spec)
rpm_deps: rpm_specs
	echo `date` - rpm_deps >> "$(LOG_FILE)"
	echo -n "RPM - Installing required build dependencies... ";
	#sudo yum clean all >> "$(LOG_FILE)" 2>&1
	# Disabling inclusions since yum-builddep does not always support '--define "_topdir xxx"'
	sed -r -i -e 's/^(%include .*)$$/#\1/' $(foreach RPM_SPEC,$(RPM_SPECS), "$(RPM_SPEC)");
	$(foreach RPM_SPEC,$(RPM_SPECS), \
		sudo yum-builddep -y "$(RPM_SPEC)" >> "$(LOG_FILE)" 2>&1 || { echo "failed (see "$(LOG_FILE)")"; exit 1; }; \
		>> "$(LOG_FILE)" 2>&1 || { echo "failed (see "$(LOG_FILE)")"; exit 1; }; \
	)
	# Re-enabling inclusions after yum-builddep
	sed -r -i -e 's/^#(%include .*)$$/\1/' $(foreach RPM_SPEC,$(RPM_SPECS), "$(RPM_SPEC)");
	echo "ok";

rpm_build: RPM_SPECS		?= $(wildcard $(RPM_BUILD_DIR)/SPECS/*-$(RPM_VERSION).spec)
rpm_build:
	echo `date` - rpm_build >> "$(LOG_FILE)"
	echo -n "RPM - Building package(s)... ";
	$(foreach RPM_SPEC,$(RPM_SPECS), \
		rpmbuild --verbose \
			--define="_topdir $(RPM_BUILD_DIR)" \
			--define="debug_package %{nil}" \
			-bb "$(RPM_SPEC)" \
		>> "$(LOG_FILE)" 2>&1 || { echo "failed (see "$(LOG_FILE)")"; exit 1; }; \
	)
	echo "ok";

rpm_post:
	echo `date` - rpm_post >> "$(LOG_FILE)"
	echo -n "RPM - Collecting RPMS from build to dists directory... ";
	mv -vf "$(RPM_BUILD_DIR)"/RPMS/*/$(RPM_NAME)*-$(RPM_VERSION)-*.rpm "$(RPM_DISTS_DIR)/" >> "$(LOG_FILE)" 2>&1 || { echo "failed (see "$(LOG_FILE)")"; exit 1; };
	#mv -vf "$(RPM_BUILD_DIR)"/SRPMS/$(RPM_NAME)*-$(RPM_VERSION)-*.rpm "$(RPM_DISTS_DIR)/" >> "$(LOG_FILE)" 2>&1 || { echo "failed (see "$(LOG_FILE)")"; exit 1; };
	echo "ok";

rpm_purge: clean
	echo `date` - rppm_purge >> "$(LOG_FILE)"
	echo -n "RPM - Removing dist directory and log files... ";
	rm -vrf "$(RPM_DISTS_DIR)" >> "$(LOG_FILE)" 2>&1 || { echo "failed (see "$(LOG_FILE)")"; exit 1; };
	rm -f *.log || { echo "failed"; exit 1; };
	echo "ok";

rpm_clean:
	echo `date` - rpm_clean >> "$(LOG_FILE)"
	echo -n "RPM - Removing build directory... ";
	rm -vrf "$(RPM_BUILD_DIR)" >> "$(LOG_FILE)" 2>&1 || { echo "failed (see "$(LOG_FILE)")"; exit 1; };
	echo "ok";
