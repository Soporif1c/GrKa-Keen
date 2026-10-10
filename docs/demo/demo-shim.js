/* Демо-данные для скриншотов: подменяет fetch, эмулируя CGI-бэкенд и Clash API */
'use strict';

(function() {
	var CONFIG = [
		'# GrKa Keen — конфигурация mihomo (Keenetic)',
		'mixed-port: 7890',
		'allow-lan: true',
		'mode: rule',
		'log-level: info',
		'ipv6: false',
		'',
		'external-controller: 0.0.0.0:9090',
		'external-ui: ui',
		"secret: ''",
		'',
		'profile:',
		'  store-selected: true',
		'  store-fake-ip: true',
		'',
		'sniffer:',
		'  enable: true',
		'  sniff:',
		'    HTTP: { ports: [80, 8080] }',
		'    TLS: { ports: [443, 8443] }',
		'',
		'dns:',
		'  enable: true',
		'  listen: 0.0.0.0:1053',
		'  enhanced-mode: fake-ip',
		'  fake-ip-range: 198.18.0.1/16',
		'  nameserver: [8.8.8.8, 1.1.1.1]',
		'',
		'# TUN только для клиентов политики «GrKa» — auto-route выключен',
		'tun:',
		'  enable: true',
		'  stack: system',
		'  device: grka-tun',
		'  auto-route: false',
		'  auto-redirect: false',
		'  auto-detect-interface: true',
		'  dns-hijack:',
		'    - any:53',
		'',
		'proxies:',
		'  - {"name":"🇳🇱 GrKa-NL","type":"vless","server":"nl.example.com","port":443,"uuid":"a1b2c3d4-...","udp":true,"tls":true,"servername":"nl.example.com","client-fingerprint":"chrome","reality-opts":{"public-key":"xTd5..."},"flow":"xtls-rprx-vision"}',
		'  - {"name":"🇩🇪 GrKa-DE","type":"vless","server":"de.example.com","port":443,"uuid":"e5f6a7b8-...","udp":true,"tls":true,"servername":"de.example.com","client-fingerprint":"chrome"}',
		'',
		'proxy-groups:',
		'  - name: Весь трафик',
		'    type: select',
		'    include-all: true',
		'    proxies: [DIRECT]',
		'',
		'rules:',
		'  - MATCH,Весь трафик'
	].join('\n');

	var LOG = [
		'2026-07-25 21:14:02 [grka] запуск mihomo (/opt/sbin/mihomo)',
		'time="2026-07-25T21:14:02" level=info msg="Start initial configuration in progress"',
		'time="2026-07-25T21:14:02" level=info msg="Geodata Loader mode: memconservative"',
		'time="2026-07-25T21:14:02" level=info msg="Mixed(http+socks) proxy listening at: [::]:7890"',
		'time="2026-07-25T21:14:02" level=info msg="DNS server listening at: [::]:1053"',
		'time="2026-07-25T21:14:03" level=info msg="TUN adapter listening at: grka-tun"',
		'time="2026-07-25T21:14:03" level=info msg="RESTful API listening at: [::]:9090"',
		'time="2026-07-25T21:14:03" level=info msg="Initial configuration complete, total time: 812ms"',
		'Маршрутизация применена: политика «GrKa» (fwmark 0xffffaab) -> grka-tun (таблица 1001)',
		'time="2026-07-25T21:14:11" level=info msg="[TCP] 192.168.1.44:51322(Телевизор зал) --> www.youtube.com:443 match RULE-SET(youtube@domain) using YouTube[🇳🇱 GrKa-NL]",',
		'time="2026-07-25T21:14:12" level=info msg="[UDP] 192.168.1.37:40011(PC) --> discord.com:443 match RULE-SET(discord@classical) using Discord[🇳🇱 GrKa-NL]"',
		'time="2026-07-25T21:14:14" level=info msg="[TCP] 192.168.1.51:52108(Mac) --> yandex.ru:443 match RULE-SET(category-ru@domain) using DIRECT"',
		'time="2026-07-25T21:14:16" level=info msg="[TCP] 192.168.1.60:44870(Oculus) --> graph.oculus.com:443 match Match using Весь трафик[DIRECT]"',
		'time="2026-07-25T21:14:19" level=info msg="[TCP] 192.168.1.37:40544(PC) --> gql.twitch.tv:443 match Or using Twitch[🇩🇪 GrKa-DE]"'
	].join('\n');

	function px(name, type, udp, delay, extra) {
		var p = { name: name, type: type, udp: udp, history: delay === null ? [] : [{ delay: delay }] };
		for (var k in (extra || {})) p[k] = extra[k];
		return p;
	}

	var PROXIES = {
		GLOBAL: { type: 'Selector', all: ['Весь трафик', 'Заблок. сервисы', 'YouTube', 'Discord', 'Twitch', 'Telegram', '🇳🇱 GrKa-NL', '🇩🇪 GrKa-DE'], now: 'Весь трафик', history: [] },
		'DIRECT': px('DIRECT', 'Direct', true, null),
		'🇳🇱 GrKa-NL': px('🇳🇱 GrKa-NL', 'Vless', true, 87),
		'🇩🇪 GrKa-DE': px('🇩🇪 GrKa-DE', 'Vless', true, 112),
		'Весь трафик': { type: 'Selector', icon: 'https://www.svgrepo.com/show/396567/globe-with-meridians.svg', all: ['DIRECT', 'Заблок. сервисы', '🇳🇱 GrKa-NL', '🇩🇪 GrKa-DE'], now: 'DIRECT', history: [] },
		'Заблок. сервисы': { type: 'Selector', icon: 'https://cdn.jsdelivr.net/gh/Koolson/Qure@master/IconSet/Color/Reject.png', all: ['DIRECT', '🇳🇱 GrKa-NL', '🇩🇪 GrKa-DE'], now: '🇳🇱 GrKa-NL', history: [] },
		'YouTube': { type: 'Selector', icon: 'https://cdn.jsdelivr.net/gh/Koolson/Qure@master/IconSet/Color/YouTube.png', all: ['Заблок. сервисы', 'DIRECT', '🇳🇱 GrKa-NL', '🇩🇪 GrKa-DE'], now: '🇳🇱 GrKa-NL', history: [] },
		'Discord': { type: 'Selector', icon: 'https://cdn.jsdelivr.net/gh/Koolson/Qure@master/IconSet/Color/Discord.png', all: ['Заблок. сервисы', 'DIRECT', '🇳🇱 GrKa-NL', '🇩🇪 GrKa-DE'], now: 'Заблок. сервисы', history: [] },
		'Twitch': { type: 'Selector', icon: 'https://cdn.jsdelivr.net/gh/Koolson/Qure@master/IconSet/Color/Twitch.png', all: ['DIRECT', 'Заблок. сервисы', '🇳🇱 GrKa-NL', '🇩🇪 GrKa-DE'], now: '🇩🇪 GrKa-DE', history: [] },
		'Telegram': { type: 'Selector', icon: 'https://cdn.jsdelivr.net/gh/Koolson/Qure@master/IconSet/Color/Telegram.png', all: ['Заблок. сервисы', 'DIRECT', '🇳🇱 GrKa-NL', '🇩🇪 GrKa-DE'], now: 'DIRECT', history: [] }
	};

	var STATUS = {
		ok: true, state: 'ok', warnings: [], paused: false, enabled: true,
		api_open: false, core_error: '', core_error_log: '',
		running: true, pid: '9184', memory: '47616',
		core_installed: true, core_version: 'v1.19.13', panel_version: '0.0.1',
		autostart: true, config_exists: true, dashboard_installed: true, compact: false,
		api_port: '9090', api_secret: '', arch: 'mipsle-softfloat',
		policy: {
			name: 'GrKa', found: true, mark: '0xffffaab', table: '1001', rci: 'ok',
			rule_ok: true, route_ok: true, tun: 'grka-tun', tun_up: true,
			clients: ['Mac', 'Oculus', 'PC', 'Телевизор зал']
		}
	};

	var API = {
		status: function() { return STATUS; },
		get_config: function() { return { exists: true, content: CONFIG }; },
		get_log: function() { return { log: LOG }; },
		journal: function() { return { ok: true, entries: [] }; },
		list_templates: function() {
			return { templates: [
				{ id: 'minimal', title: 'Минимальный (селектор «Весь трафик»: напрямую или через прокси)' },
				{ id: 'services', title: 'Сервисы и селекторы (YouTube, Discord, Telegram, AI и др.)' }
			] };
		},
		list_backups: function() {
			return { backups: ['config-20260725-211358.yaml', 'config-20260725-205940.yaml', 'config-20260724-183122.yaml'] };
		},
		check_updates: function() {
			return { core_current: 'v1.19.13', core_latest: 'v1.19.13', panel_current: '0.0.1', panel_latest: '0.0.1', panel_update: false };
		},
		check_config: function() { return { ok: true, output: 'configuration file ' + '/opt/etc/mihomo/config.yaml' + ' test is successful' }; },
		task_status: function() { return { running: false, log: '' }; }
	};

	window.fetch = function(url, opts) {
		var data = null;
		if (String(url).indexOf('cgi-bin/api') >= 0) {
			var body = {};
			try { body = JSON.parse((opts && opts.body) || '{}'); } catch (e) {}
			data = API[body.method] ? API[body.method](body.params || {}) : { ok: true };
		} else if (String(url).indexOf('/proxies') >= 0) {
			data = { proxies: PROXIES };
		} else if (String(url).indexOf('/providers/') >= 0) {
			data = { providers: {} };
		} else {
			data = {};
		}
		return Promise.resolve({
			ok: true,
			json: function() { return Promise.resolve(data); }
		});
	};

	/* автосценарий для скриншота модалки генератора прокси */
	window.addEventListener('DOMContentLoaded', function() {
		var params = new URLSearchParams(window.location.search);
		if (params.get('modal') !== 'addproxy') return;
		window.setTimeout(function() {
			var btns = Array.prototype.slice.call(document.querySelectorAll('button'));
			var open = btns.find(function(b) { return b.textContent === 'Добавить прокси из ссылки'; });
			if (open) open.click();
			window.setTimeout(function() {
				var input = document.querySelector('#modal-root input[type=text]');
				if (!input) return;
				input.value = 'vless://a1b2c3d4-e5f6-7a8b-9c0d-e1f2a3b4c5d6@nl.example.com:443?security=reality&sni=cdn.example.com&fp=chrome&pbk=xTd5mJ0Zx1vQ&sid=6ba85179&type=tcp&flow=xtls-rprx-vision#%F0%9F%87%B3%F0%9F%87%B1%20GrKa-NL';
				var gen = Array.prototype.slice.call(document.querySelectorAll('#modal-root button'))
					.find(function(b) { return b.textContent === 'Сгенерировать'; });
				if (gen) gen.click();
			}, 400);
		}, 600);
	});
})();
