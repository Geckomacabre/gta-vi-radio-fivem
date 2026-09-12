(function () {
    'use strict';

    var REFERENCE_HEIGHT = 1080; // the layout numbers in config.lua are 1080p

    var root     = document.documentElement;
    var radio    = document.getElementById('radio');
    var track    = document.getElementById('track');
    var iconL    = document.getElementById('icon-left');
    var iconR    = document.getElementById('icon-right');
    var elLine   = document.getElementById('info-line');
    var elStat   = document.getElementById('station');
    var elTitle  = document.getElementById('title');
    var elArtist = document.getElementById('artist');

    var hud       = null;
    var stations  = [];
    var index     = 0;
    var muted     = false;
    var isOpen    = false;
    var flashTimer = null;

    // -- helpers -----------------------------------------------------------

    function rgba(str, fallback) {
        var parts = String(str || '').split(',').map(function (n) { return parseFloat(n); });
        if (parts.length < 3 || parts.some(isNaN)) return fallback;
        var a = parts.length > 3 ? parts[3] / 255 : 1;
        return 'rgba(' + parts[0] + ',' + parts[1] + ',' + parts[2] + ',' + a.toFixed(3) + ')';
    }

    function scale() {
        return window.innerHeight / REFERENCE_HEIGHT;
    }

    function px(n) { return n + 'px'; }

    function applyHud(cfg) {
        hud = cfg;
        var s = root.style;
        var font = cfg.fontPx || 94;

        s.setProperty('--s', scale());
        s.setProperty('--icon', px(cfg.iconSize));
        s.setProperty('--spacing', px(cfg.spacing));
        s.setProperty('--top', px(cfg.top));
        s.setProperty('--border', px(cfg.borderSize));
        s.setProperty('--box', rgba(cfg.boxColor, 'rgba(0,0,0,0.667)'));
        s.setProperty('--box-active', rgba(cfg.boxActiveColor, 'rgba(45,45,45,0.863)'));
        s.setProperty('--outline', rgba(cfg.borderColor, 'rgba(255,255,255,0.353)'));
        s.setProperty('--outline-active', rgba(cfg.borderActiveColor, 'rgba(255,255,255,1)'));
        s.setProperty('--slide', (cfg.slideTime || 110) + 'ms');
        s.setProperty('--side-gap', px(cfg.sideGap));
        s.setProperty('--left-icon-h', px(cfg.leftIconHeight));
        s.setProperty('--right-icon-h', px(cfg.rightIconHeight));
        s.setProperty('--line-y', px(cfg.infoLineY));
        s.setProperty('--line-w', px(cfg.infoLineWidth));
        s.setProperty('--line-h', px(cfg.infoLineHeight));
        s.setProperty('--station-y', px(cfg.stationY));
        s.setProperty('--station-size', px(font * cfg.stationScale));
        s.setProperty('--title-y', px(cfg.titleY));
        s.setProperty('--title-size', px(font * cfg.titleScale));
        s.setProperty('--artist-y', px(cfg.artistY));
        s.setProperty('--artist-size', px(font * cfg.artistScale));

        iconL.src = cfg.leftIcon;
        iconL.style.display = cfg.sideIcons ? '' : 'none';
        iconR.style.display = cfg.sideIcons ? '' : 'none';
        elLine.style.display = cfg.infoLineHeight > 0 ? '' : 'none';
    }

    function buildTrack(list) {
        stations = list || [];
        track.innerHTML = '';

        stations.forEach(function (station) {
            var tile = document.createElement('div');
            tile.className = 'tile';

            if (station.logo && (!hud || hud.stationLogos !== false)) {
                var img = document.createElement('img');
                img.src = station.logo;
                // A missing PNG should not leave an empty box.
                img.onerror = function () {
                    tile.innerHTML = '';
                    tile.appendChild(fallbackNode(station.label));
                };
                tile.appendChild(img);
            } else {
                tile.appendChild(fallbackNode(station.label));
            }

            track.appendChild(tile);
        });
    }

    function fallbackNode(label) {
        var span = document.createElement('span');
        span.className = 'fallback';
        span.textContent = label || '';
        return span;
    }

    function render() {
        var tiles = track.children;
        for (var i = 0; i < tiles.length; i++) {
            tiles[i].classList.toggle('active', i === index);
        }

        if (hud) {
            var step = hud.spacing * scale();
            track.style.transform = 'translateX(' + (-(index * step) - step / 2) + 'px)';
        }

        var station = stations[index];
        elStat.textContent = station ? station.label : '';

        radio.classList.toggle('muted', muted);
        if (hud) iconR.src = muted ? hud.unmuteIcon : hud.rightIcon;
    }

    function renderNowPlaying(title, artist) {
        var station = stations[index];
        var isOff = station && station.off;

        if (isOff) {
            elTitle.textContent = '';
            elArtist.textContent = '';
            return;
        }

        if (title) {
            elTitle.textContent = title;
            elArtist.textContent = artist || '';
            return;
        }

        // No live track feed: fall back to the station genre, like the wheel
        // does in the singleplayer mod when a track has no metadata.
        elTitle.textContent = '';
        var wantsGenre = !hud || hud.subtitle === 'genre';
        elArtist.textContent = (wantsGenre && station && station.genre) ? station.genre : '';
    }

    function setVisible(visible) {
        radio.classList.toggle('hidden', !visible);
    }

    // -- messages ----------------------------------------------------------

    window.addEventListener('message', function (event) {
        var data = event.data || {};

        if (data.action === 'state') {
            if (data.hud) applyHud(data.hud);
            if (data.list) buildTrack(data.list);

            index  = typeof data.index === 'number' ? data.index : index;
            muted  = !!data.muted;
            isOpen = !!data.open;

            render();
            renderNowPlaying(data.title, data.artist);

            if (flashTimer) { clearTimeout(flashTimer); flashTimer = null; }
            setVisible(isOpen);
            return;
        }

        if (data.action === 'flash') {
            muted = !!data.muted;
            render();
            setVisible(true);
            if (flashTimer) clearTimeout(flashTimer);
            flashTimer = setTimeout(function () {
                if (!isOpen) setVisible(false);
                flashTimer = null;
            }, 1400);
            return;
        }

        if (data.action === 'sound') {
            var audio = new Audio(data.file);
            audio.volume = Math.max(0, Math.min(1, data.volume));
            audio.play().catch(function () { /* autoplay gate, ignore */ });
            return;
        }
    });

    window.addEventListener('resize', function () {
        root.style.setProperty('--s', scale());
        render();
    });

    root.style.setProperty('--s', scale());
}());
