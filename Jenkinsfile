#!groovy

/*
 * This work is protected under copyright law in the Kingdom of
 * The Netherlands. The rules of the Berne Convention for the
 * Protection of Literary and Artistic Works apply.
 * Digital Me B.V. is the copyright owner.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *	   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Load Jenkins shared libraries common to all projects
def libLazy = [
	remote:			'https://github.com/digital-me/jenkins-lib-lazy.git',
	branch:			'stable',
	credentialsId:	null,
]

library(
	identifier: "libLazy@${libLazy.branch}",
	retriever: modernSCM([
		$class:			'GitSCMSource',
		remote:			libLazy.remote,
		credentialsId:	libLazy.credentialsId
	])
)

// Load Jenkins shared libraries to customize this project
def libCustom = [
	remote:			'ssh://git@code.in.digital-me.nl:2222/DEVops/JenkinsLibCustom.git',
	branch:			'stable',
	credentialsId:	'bot-ci-dgm-rsa',
]

library(
	identifier: "libCustom@${libCustom.branch}",
	retriever: modernSCM([
		$class:			'GitSCMSource',
		remote:			libCustom.remote,
		credentialsId:	libCustom.credentialsId
	])
)

// Load Jenkins shared libraries for rpmMake utils
def libRpmMake = [
	remote:			'https://github.com/digital-me/rpmMake.git',
	branch:			env.BRANCH_NAME,
	credentialsId:	null,
]

library(
	identifier: "libRpmMake@${libRpmMake.branch}",
	retriever: modernSCM([
		$class:			'GitSCMSource',
		remote:			libRpmMake.remote,
		credentialsId:	libRpmMake.credentialsId
	])
)

// Define the remotes and the working and deploy branches
def remote = 'origin'
def workingBranch = 'master'
def releaseBranch = 'stable'

// Initialize configuration
lazyConfig(
	name: 		   'rpmmake',
	env: 		   [
		RELEASE:    true,
		DRYRUN:     false,
		TARGET_DIR: 'target',
		GIT_CRED:   'bot-ci-dgm-rsa',
	],
	inLabels:      [ 'centos6', 'centos7' ],
	onLabels:      [ default: 'linux', docker: 'docker', ],
	noIndex:	   "(${releaseBranch}|.+_.+)",	// Avoid automatic indexing for release and private branches
	compressLog:   false,
	timestampsLog: true,
)

lazyStage {
	name = 'validate'
	onlyif = ( lazyConfig['branch'] != releaseBranch ) // Skip when releasing
	tasks = [
		pre: {
			def currentVersion = gitLastTag()
			currentBuild.displayName = "#${env.BUILD_NUMBER} ${currentVersion}"
		},
		run: {
			echo "If this runs, it means the lib(s) can be parsed and run until this point"
		},
	]
}

lazyStage {
	name = 'test'
	onlyif = ( lazyConfig['branch'] != releaseBranch ) // Skip when releasing
	tasks = [
		run: {
			def version = env.VERSION ?: gitLastTag()
			def release = version ==~ /.+-.+/ ? version.split('-')[1] : '1'
			version = version - ~/-\d+/
			sh(
"""
DIST=\"\${LAZY_LABEL%%-*}\${LAZY_LABEL##*-}-\$(arch)\"
make \
RPM_NAME='rpmMake' \
RPM_VERSION=${version} \
RPM_RELEASE=${release} \
RPM_TARGET_DIR=\$(pwd)/${env.TARGET_DIR} \
RPM_DISTS_DIR=\$(pwd)/${env.TARGET_DIR}/dists/\${DIST} \
LOG_FILE=/dev/stdout
"""
			)
			sh("DIST=\"\${LAZY_LABEL%%-*}\${LAZY_LABEL##*-}-\$(arch)\" && sudo yum -y install \$(pwd)/${env.TARGET_DIR}/dists/\${DIST}/*.rpm")
		},
		in: '*', on: 'docker',
	]
}

// Release stage only if criteria are met
lazyStage {
	name = 'release'
	onlyif = ( lazyConfig['branch'] == workingBranch && lazyConfig.env.RELEASE )
	// Ask version if release flag and set and we are in the branch to fork release from
	input = [
		message: 'Version string',
		parameters: [string(
			defaultValue: '',
			description: "Version to be release: 'build' (default), 'micro', 'minor', 'major' or a specific string (i.e.: 1.2.3-4)",
			name: 'VERSION'
		)]
	]
	tasks = [
		run: {
			gitAuth(env.GIT_CRED, {
				// Define next version based on optional input
				def currentVersion = gitLastTag()
				def nextVersion = null
				if (env.lazyInput) {
					if (env.lazyInput ==~ /[a-z]+/) {
						nextVersion = bumpVersion(env.lazyInput, currentVersion)
					} else {
						nextVersion = env.lazyInput
					}
				} else {
					nextVersion = bumpVersion('build', currentVersion)
				}
				// Merge changes from working into release branch
				gitMerge(workingBranch, releaseBranch)
				// Tag and publish changes in release branch
				gitTag("${nextVersion}")
				gitPush(remote, "${releaseBranch} ${nextVersion}")
				// Update the displayed version for this build
				currentVersion = gitLastTag()
				currentBuild.displayName = "#${env.BUILD_NUMBER} ${currentVersion}"
			})
		},
		// Can not be done in parallel
	]
}
