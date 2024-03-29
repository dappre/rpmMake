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
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import groovy.transform.Field
import org.jenkins.ci.lazy.Logger

@Field private logger = new Logger(this)

def getFromChangelog() {
    def rpmChangelogPath = 'rpm/changelog'
    def rpmChangelog = readFile(encoding: 'UTF-8', file: rpmChangelogPath)
    def m = rpmChangelog =~ /\* [^\n]+ - ([^\s]+)\n/
    if (m) {
        logger.trace('get', "Matcher for version in ${rpmChangelogPath} returned ${m}")
        logger.debug('get', "Retrieved version = ${m[0][1]}")
        return m[0][1]
    }
    else {
        logger.warn('get', "Could not find version in ${rpmChangelogPath}")
        return null
    }
}

def call() {
	logger.debug('Called without argument - calling getFromChangelog')
	return getFromChangelog()
}
