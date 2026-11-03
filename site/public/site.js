/*
 * Click-to-play for the web build, as a progressive enhancement.
 *
 * Without this script "Start the game" is a plain link to play/, which is the
 * game exactly as Godot exported it, on a page of its own. With it, on a screen
 * big enough to play on and with a mouse or trackpad, the same link instead
 * swaps the poster for an iframe of play/ in place.
 *
 * Why an iframe of play/ rather than the engine mounted into this page: the
 * export is single-threaded (docs/ci.md, "The COOP/COEP decision"), so it needs
 * no cross-origin isolation and runs in any same-origin frame -- the shell
 * Godot generates can be published untouched, and this page stays plain HTML.
 *
 * Why only on a click: the engine is tens of megabytes. Nobody who came to read
 * about the game or fetch the APK should download it.
 *
 * Why not on a phone: the game wants the whole screen in landscape, and an
 * iframe inside a scrolling page competes with the page for every touch. There
 * the link is left alone and the game opens full-window.
 */
(function () {
	"use strict";

	var stage = document.querySelector("[data-stage]");
	var start = document.querySelector("[data-start]");
	var fullscreen = document.querySelector("[data-fullscreen]");
	if (!stage || !start) {
		return;
	}

	function embedHere() {
		return window.matchMedia("(min-width: 760px) and (pointer: fine)").matches;
	}

	start.addEventListener("click", function (event) {
		if (!embedHere()) {
			return; // follow the link
		}
		event.preventDefault();

		var frame = document.createElement("iframe");
		frame.src = start.getAttribute("href");
		frame.title = "Swordknights, running in the browser";
		frame.setAttribute("allow", "fullscreen; gamepad; autoplay");
		stage.replaceChildren(frame);

		// Keys go to whichever document has focus. Without this the first few
		// presses would scroll this page instead of moving the character.
		frame.addEventListener("load", function () {
			frame.focus();
		});
		frame.focus();

		if (fullscreen && document.fullscreenEnabled) {
			fullscreen.hidden = false;
			fullscreen.addEventListener("click", function () {
				frame.requestFullscreen().then(function () {
					frame.focus();
				}, function () {});
			});
		}
	});
}());
