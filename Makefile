all: help

##
##  __________                             __  .__
##  \______   \ ____ ______   ____________/  |_|__| ____    ____
##   |       _// __ \\____ \ /  _ \_  __ \   __\  |/    \  / ___\
##   |    |   \  ___/|  |_> >  <_> )  | \/|  | |  |   |  \/ /_/  >
##   |____|_  /\___  >   __/ \____/|__|   |__| |__|___|  /\___  /
##          \/     \/|__|                              \//_____/
##

.PHONY : help
help : Makefile
	@sed -n 's/^##\s//p' $<

PROJECT="numerics"
SHELL := /bin/bash
ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
UID=$(shell id -u)


define execute
	docker-compose -p ${PROJECT} run \
		-v ~/.ssh/id_rsa:/root/.ssh/id_rsa:ro \
		-v ~/.ssh/id_rsa.pub:/root/.ssh/id_rsa.pub:ro \
		-v ~/.ssh/known_hosts:/root/.ssh/known_hosts:ro \
		-v ~/.gitconfig:/root/.gitconfig:ro \
		-v ~/.composer/auth.json:/root/.composer/auth.json:ro \
		--rm \
		--no-deps \
		--entrypoint=/bin/bash \
		-e HOST_USER=${UID} \
		-e TERM=xterm-256color \
		webserver -c "$1"
endef

define execute_test
	docker-compose -p ${PROJECT} run \
		-v ~/.ssh/id_rsa:/root/.ssh/id_rsa:ro \
		-v ~/.ssh/id_rsa.pub:/root/.ssh/id_rsa.pub:ro \
		-v ~/.ssh/known_hosts:/root/.ssh/known_hosts:ro \
		-v ~/.gitconfig:/root/.gitconfig:ro \
		-v ~/.composer/auth.json:/root/.composer/auth.json:ro \
		--rm \
		--no-deps \
		--entrypoint=/bin/bash \
		-e HOST_USER=${UID} \
		-e TERM=xterm-256color \
		webserver -c "$1"
endef

define docker_reconnect
	docker network disconnect $1 $2 && \
	docker network connect $1 $2 --alias $3
endef

###########
# Docker #
###########

## 	start:			starts services (docker)
.PHONY : start
start:
	@docker-compose -p ${PROJECT} up -d --no-build

## 	stop:			stops containers (docker)
.PHONY : stop
stop:
	@docker-compose -p ${PROJECT} stop

## 	restart:			restart containers (docker)
.PHONY : restart
restart: stop start

## 	pull:			pulls docker images from container registry (docker)
.PHONY : pull
pull:
	docker-compose \
		-p ${PROJECT} \
		pull

## 	destroy:			stops containers and delete them and their volumes (docker)
.PHONY : destroy
destroy:
	@docker-compose -p ${PROJECT} down -v

## 	rm:			stops containers and delete them, volumes are kept  (docker)
.PHONY : rm
rm:
	@docker-compose -p ${PROJECT} rm -s -f

## 	status:			shows container statuses (docker)
.PHONY : status
status:
	@docker-compose -p ${PROJECT} ps

## 	logs:			shows container logs (docker)
.PHONY : logs
logs:
	@docker-compose -p ${PROJECT} logs -f -t

## 	shell:			runs a container with an interactive shell (docker)
.PHONY : shell
shell:
	docker-compose -p ${PROJECT} run \
    		-v ~/.ssh/id_rsa:/root/.ssh/id_rsa:ro \
    		-v ~/.ssh/id_rsa.pub:/root/.ssh/id_rsa.pub:ro \
    		-v ~/.ssh/known_hosts:/root/.ssh/known_hosts:ro \
    		-v ~/.gitconfig:/root/.gitconfig:ro \
    		-v ~/.composer/auth.json:/root/.composer/auth.json:ro \
    		--rm \
    		--no-deps \
    		-e HOST_USER=${UID} \
    		-e TERM=xterm-256color \
    		webserver /bin/bash -l

########
# Test #
########

## 	test:				runs unit tests (PHPUnit)
.PHONY : test
test:
	-@docker-compose -p ${PROJECT}_test -f docker-compose.test.yml run --entrypoint /bin/bash -e TERM=xterm-256color webserver -c "vendor/phpunit/phpunit/phpunit -c phpunit.xml.dist --testdox"

## 	test@coverage:			runs unit tests with coverage
.PHONY : test@coverage
test@coverage:
	-@docker-compose -p ${PROJECT}_test -f docker-compose.test.yml run --entrypoint /bin/bash -e TERM=xterm-256color webserver -c "vendor/phpunit/phpunit/phpunit -c phpunit.xml.dist --coverage-text --testdox"

## 	test@acceptance:		runs acceptance tests (docker)
.PHONY : test@acceptance
test@acceptance:
	-@docker-compose -p ${PROJECT}_test -f docker-compose.test.yml up -d
	-@docker-compose -p ${PROJECT}_test -f docker-compose.test.yml run --entrypoint /bin/bash -e TERM=xterm-256color webserver -c "make setup@docker && bin/behat"

###########
# Install #
###########

## 	install:			installs dependencies and some other configuration tasks
.PHONY : install
install:
	-@$(call execute,composer install --no-interaction);

## 	setup:			sets up the environment
.PHONY : setup
setup: install
	-@$(call execute,make setup@docker) && echo '=> Ready :)';

## 	setup@docker:			sets up the environment
.PHONY : setup@docker
setup@docker:
	bin/console doctrine:database:drop --force --if-exists --connection store
	bin/console doctrine:database:drop --force --if-exists --connection projection
	bin/console doctrine:database:create --if-not-exists --connection store
	bin/console doctrine:database:create --if-not-exists --connection projection
	bin/console doctrine:migrations:migrate --no-interaction

###############
# Environment #
###############

## 	configure:				configures the environment
.PHONY : configure
configure: hooks
	-@cp -f .env.dist .env > /dev/null 2>&1
	-@docker network create letgo > /dev/null 2>&1

## 	hooks:				set up git hooks
.PHONY : hooks
hooks:
	@-cp -f vendor/bruli/php-git-hooks/src/PhpGitHooks/Infrastructure/Hook/pre-commit .git/hooks
	@-cp -f vendor/bruli/php-git-hooks/src/PhpGitHooks/Infrastructure/Hook/pre-push .git/hooks
	@-cp -f vendor/bruli/php-git-hooks/src/PhpGitHooks/Infrastructure/Hook/commit-msg .git/hooks
	@-chmod +x .git/hooks/pre-commit
	@-chmod +x .git/hooks/pre-push
	@-chmod +x .git/hooks/commit-msg

## 	fix-permissions:		fixes permissions of project directories
.PHONY : fix-permissions
fix-permissions:
	@chmod +rwx tmp logs
	@echo "Permissions fixed"


########
# Tools #
########

##		redis-monitor:			executes redis-cli monitor command to debug redis commands
redis-monitor:
	docker-compose -p ${PROJECT} exec reporting_redis redis-cli monitor

##################
# Lint & Metrics #
##################

## 	check-style:			checks code style
.PHONY : check-style
check-style:
	bin/phpcs --standard=./ruleset.xml --dry-run --diff

## 	fix-style:			fix code style
.PHONY : fix-style
fix-style:
	bin/php-cs-fixer fix src/ --rules=@PSR2
	bin/php-cs-fixer fix tests/ --rules=@PSR2

## 	phpmetrics:			generates phpmetrics of the project
.PHONY : phpmetrics
phpmetrics:
	~/.composer/vendor/phpmetrics/phpmetrics/bin/phpmetrics --report-html=build/metrics .

###########
#  Build  #
###########

## 	build@docker:			build docker images locally
.PHONY : build@docker
build@docker:
	docker-compose -f docker-compose.build.yml build --no-cache

## 	push@docker:			pushes images to Docker registry
.PHONY : push@docker
push@docker:
	docker-compose -f docker-compose.build.yml push

## 	build-clean:			cleans build directory
.PHONY : build-clean
build-clean:
	rm -Rf build/*

## 	build:				builds the project
.PHONY : build
build@prod: build-clean
	export ENV=prod
	export SYMFONY_ENV=prod

    # Composer
	rm -f composer.phar
	wget https://getcomposer.org/composer.phar
	php composer.phar install --prefer-dist --no-progress

	# PHPUnit
	vendor/phpunit/phpunit/phpunit \
		-c phpunit.xml.dist \
		--log-junit build/phpunit/junit.xml \
		--coverage-clover build/phpunit/clover.xml

	php composer.phar install --no-dev --prefer-dist --no-progress --optimize-autoloader
	php composer.phar dump-autoload --optimize
