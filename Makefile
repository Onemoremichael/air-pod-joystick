.PHONY: build test app run clean

build:
	swift build

test:
	swift test

app:
	./scripts/package-app.sh

run: app
	open .build/PodStick.app

clean:
	swift package clean
