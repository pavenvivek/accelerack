
VER=v0.4

SERVER=tank.cs.indiana.edu
SERVER_USER=rrnewton
SERVER_PATH=/l/html/homes.soic.indiana.edu/classes/spring2016/csci/h211-rrnewton/accelerack/$(VER)/

.PHONY: all build send

default: build
all: build send

build:
	scribble --redirect-main https://docs.racket-lang.org/ +m manual.scrbl

send:
	ssh $(SERVER_USER)@$(SERVER) mkdir -p $(SERVER_PATH)
	scp manual-* manual.html $(SERVER_USER)@$(SERVER):$(SERVER_PATH)
	ssh $(SERVER_USER)@$(SERVER) chmod ugo+rX -R $(SERVER_PATH)

