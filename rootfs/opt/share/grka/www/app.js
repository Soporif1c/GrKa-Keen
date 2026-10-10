/* GrKa Keen - веб-панель управления mihomo для Keenetic */
'use strict';

/* ---------- Помощники ---------- */

function el(tag, attrs) {
	var node = document.createElement(tag);
	attrs = attrs || {};
	for (var k in attrs) {
		if (k === 'class') node.className = attrs[k];
		else if (k === 'style') node.style.cssText = attrs[k];
		else if (k.slice(0, 2) === 'on') node[k] = attrs[k];
		else if (k === 'checked') { if (attrs[k]) node.checked = true; }
		else if (k === 'disabled') { if (attrs[k]) node.disabled = true; }
		else node.setAttribute(k, attrs[k]);
	}
	for (var i = 2; i < arguments.length; i++) appendAny(node, arguments[i]);
	return node;
}

function appendAny(node, child) {
	if (child === null || child === undefined || child === false) return;
	if (Array.isArray(child)) { child.forEach(function(c) { appendAny(node, c); }); return; }
	if (typeof child === 'string' || typeof child === 'number') {
		node.appendChild(document.createTextNode(String(child)));
		return;
	}
	node.appendChild(child);
}

function api(method, params) {
	return window.fetch('cgi-bin/api', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json', 'X-GrKa-Request': '1' },
		body: JSON.stringify({ method: method, params: params || {} })
	}).then(function(r) {
		if (!r.ok) throw new Error('HTTP ' + r.status);
		return r.json();
	});
}

function notify(msg, type) {
	var box = document.getElementById('notify');
	var n = el('div', { 'class': 'note ' + (type || 'info') }, msg);
	box.appendChild(n);
	window.setTimeout(function() { n.remove(); }, type === 'error' ? 8000 : 5000);
}

function modal(title, nodes, foot) {
	closeModal();
	var m = el('div', { 'class': 'modal' }, el('h3', {}, title), nodes,
		foot ? el('div', { 'class': 'foot' }, foot) : null);
	var ov = el('div', { 'class': 'overlay', onclick: function(ev) { if (ev.target === ov) closeModal(); } }, m);
	document.getElementById('modal-root').appendChild(ov);
	return m;
}

function closeModal() {
	document.getElementById('modal-root').innerHTML = '';
}

function fmtMem(kb) {
	var n = parseInt(kb, 10);
	if (isNaN(n) || n <= 0) return '';
	if (n >= 1024) return (n / 1024).toFixed(1) + ' МБ';
	return n + ' КБ';
}

/* Модалка выполнения фоновой задачи с живым логом */
function runTask(startPromise, title) {
	return startPromise.then(function(res) {
		if (!res || !res.started) {
			notify((res && res.error) || 'Не удалось запустить задачу', 'error');
			return;
		}
		var pre = el('pre', { 'class': 'term', 'style': 'max-height:50vh' }, 'Запуск...');
		var btn = el('button', { 'class': 'btn', disabled: true }, 'Выполняется...');
		modal(title, [pre], [btn]);
		var timer = window.setInterval(function() {
			api('task_status').then(function(t) {
				pre.textContent = t.log || '...';
				pre.scrollTop = pre.scrollHeight;
				if (!t.running) {
					window.clearInterval(timer);
					btn.disabled = false;
					btn.textContent = 'Закрыть';
					btn.onclick = function() { closeModal(); refreshActiveTab(); };
				}
			}).catch(function() { /* панель может перезапускаться при самообновлении */ });
		}, 2000);
	});
}

/* ---------- Каркас вкладок ---------- */

var activeTab = 'status';
var pollTimers = [];

function addPoll(fn, seconds) {
	pollTimers.push(window.setInterval(fn, seconds * 1000));
}

function clearPolls() {
	pollTimers.forEach(function(t) { window.clearInterval(t); });
	pollTimers = [];
}

function showTab(name) {
	activeTab = name;
	clearPolls();
	closeModal();
	document.querySelectorAll('.tabs button').forEach(function(b) {
		b.classList.toggle('active', b.getAttribute('data-tab') === name);
	});
	var c = document.getElementById('content');
	c.innerHTML = '';
	TABS[name].render(c);
}

function refreshActiveTab() {
	showTab(activeTab);
}

/* ---------- Вкладка «Статус» ---------- */

var statusTab = {
	paused: false,
	el: {},

	render: function(root) {
		var u = this.el = {};
		var self = this;

		u.state = el('span', {}, '—');
		u.details = el('span', { 'class': 'hint' }, '');
		u.coreVersion = el('span', {}, '—');
		u.coreVersion2 = el('span', {}, '—');
		u.coreLatest = el('span', {}, '—');
		u.panelVersion = el('span', {}, '—');
		u.panelLatest = el('span', {}, '—');
		u.dashState = el('span', {}, '—');
		u.dashLink = el('a', { href: '#', target: '_blank', 'style': 'margin-left:1em;display:none' }, 'Открыть дашборд ↗');

		u.autostart = el('input', {
			type: 'checkbox',
			onchange: function(ev) { self.serviceAction(ev.target.checked ? 'enable' : 'disable'); }
		});
		u.compact = el('input', {
			type: 'checkbox',
			onchange: function(ev) {
				var on = ev.target.checked;
				runTask(api('set_compact', { enabled: on ? '1' : '0' }),
					on ? 'Включение компактного режима' : 'Выключение компактного режима');
			}
		});

		u.btnStart = el('button', { 'class': 'btn green', onclick: function() { self.serviceAction('start'); } }, 'Запустить');
		u.btnStop = el('button', { 'class': 'btn red', onclick: function() { self.serviceAction('stop'); } }, 'Остановить');
		u.btnRestart = el('button', { 'class': 'btn', onclick: function() { self.serviceAction('restart'); } }, 'Перезапустить');
		u.btnCoreUpdate = el('button', { 'class': 'btn primary', onclick: function() {
			runTask(api('update_core', { version: '' }), 'Обновление ядра mihomo');
		} }, 'Обновить ядро');
		u.btnPanelUpdate = el('button', { 'class': 'btn primary', disabled: true, onclick: function() {
			runTask(api('update_panel'), 'Обновление панели GrKa Keen');
		} }, 'Обновить панель');
		u.btnCheckUpdates = el('button', { 'class': 'btn', onclick: function() { self.checkUpdates(); } }, 'Проверить обновления');
		u.btnDashInstall = el('button', { 'class': 'btn primary', onclick: function() {
			runTask(api('install_dashboard'), 'Установка дашборда MetaCubeXD');
		} }, 'Установить / обновить дашборд');
		u.warnings = el('div', { 'class': 'warnbox', 'style': 'display:none' });
		u.wdState = el('span', {}, '—');
		u.coreError = el('pre', { 'class': 'term', 'style': 'display:none;margin-top:.5em;max-height:12em' }, '');
		u.btnPause = el('button', { 'class': 'btn', onclick: function() {
			api(self.paused ? 'service.resume' : 'service.pause').then(function(res) {
				notify((res && (res.message || res.error)) || 'Готово', res && res.ok ? 'info' : 'error');
				self.refresh();
			});
		} }, 'Поставить VPN на паузу');
		u.btnSecureApi = el('button', { 'class': 'btn primary', 'style': 'display:none', onclick: function() {
			api('expert.secure_api').then(function(res) {
				notify((res && (res.message || res.error)) || 'Готово', res && res.ok ? 'info' : 'error');
				self.refresh();
			});
		} }, 'Защитить API паролем');
		u.token = el('input', { type: 'text', 'style': 'width:22em', placeholder: 'токен из Keenetic: Пользователи и доступ' });
		u.btnTokenSave = el('button', { 'class': 'btn', 'style': 'margin-left:8px', onclick: function() {
			api('settings.set', { rci_token: u.token.value.trim() }).then(function(res) {
				if (res && res.ok) { notify('Токен сохранён'); u.token.value = ''; self.refresh(); }
				else notify((res && res.error) || 'Ошибка сохранения', 'error');
			});
		} }, 'Сохранить');

		/* --- Политика Keenetic --- */
		u.policyName = el('input', { type: 'text', 'style': 'width:12em', value: 'GrKa' });
		u.btnPolicySave = el('button', { 'class': 'btn', 'style': 'margin-left:8px', onclick: function() {
			api('set_policy', { name: u.policyName.value.trim() }).then(function(res) {
				if (res && res.ok) { notify('Имя политики сохранено: ' + res.name); self.refresh(); }
				else notify((res && res.error) || 'Ошибка сохранения', 'error');
			});
		} }, 'Сохранить');
		u.policyState = el('div', {}, '—');
		u.policyRoute = el('div', {}, '—');
		u.policyClients = el('div', { 'class': 'chips' });
		u.btnPolicyApply = el('button', { 'class': 'btn primary', onclick: function() {
			api('policy_apply').then(function(res) {
				notify(res.output || (res.ok ? 'Готово' : 'Ошибка'), res.ok ? 'info' : 'error');
				self.refresh();
			});
		} }, 'Применить маршрутизацию');

		function row(label, field) {
			return el('div', { 'class': 'row' },
				el('label', { 'class': 'title' }, label),
				el('div', { 'class': 'field' }, field));
		}

		appendAny(root, [
			el('h2', {}, 'GrKa Keen'),
			el('div', { 'class': 'descr' },
				'Панель управления mihomo для Keenetic. Трафик заворачивается только для клиентов политики доступа Keenetic — остальные устройства работают как обычно.'),
			u.warnings,

			el('div', { 'class': 'section' },
				el('h3', {}, 'Сервис mihomo'),
				row('Состояние', [u.state, ' ', u.details]),
				row('Сторож', [u.wdState, u.coreError]),
				row('Версия ядра', u.coreVersion),
				row('Автозапуск', u.autostart),
				row('Компактный режим', [
					u.compact,
					el('span', { 'class': 'hint', 'style': 'margin-left:.5em' },
						'ядро хранится сжатым в /opt (~12 МБ вместо ~35) и распаковывается в RAM при старте')
				]),
				row('Управление', el('div', { 'class': 'btnrow' }, [u.btnStart, u.btnStop, u.btnRestart, u.btnSecureApi]))),

			el('div', { 'class': 'section' },
				el('h3', {}, 'Политика доступа Keenetic'),
				el('div', { 'class': 'descr' }, [
					'Через mihomo ходят только клиенты этой политики. Создайте её в веб-интерфейсе Keenetic: ',
					el('i', {}, 'Приоритеты подключений → Политики доступа в интернет → Добавить политику'),
					' (имя как ниже, подключения политике НЕ назначайте — тогда при остановленном mihomo у её клиентов не будет утечек), затем добавьте клиентов на вкладке «Применение политик».'
				]),
				row('Имя политики', [u.policyName, u.btnPolicySave]),
				row('Состояние', u.policyState),
				row('Маршрутизация', u.policyRoute),
				row('Клиенты политики', u.policyClients),
				row('Токен RCI', [u.token, u.btnTokenSave, el('div', { 'class': 'hint' }, 'Нужен на KeeneticOS 5.2 и новее. Пустое поле и «Сохранить» — удалить токен')]),
				row('Действия', el('div', { 'class': 'btnrow' }, [u.btnPolicyApply, u.btnPause]))),

			el('div', { 'class': 'section' },
				el('h3', {}, 'Обновления'),
				row('Ядро mihomo', el('span', {}, [u.coreVersion2, el('span', { 'class': 'hint' }, ' → последняя: '), u.coreLatest])),
				row('Панель GrKa Keen', el('span', {}, [u.panelVersion, el('span', { 'class': 'hint' }, ' → последняя: '), u.panelLatest])),
				row('Действия', el('div', { 'class': 'btnrow' }, [u.btnCheckUpdates, u.btnCoreUpdate, u.btnPanelUpdate]))),

			el('div', { 'class': 'section' },
				el('h3', {}, 'Дашборд (Clash API)'),
				el('div', { 'class': 'descr' }, 'MetaCubeXD — веб-дашборд mihomo: соединения, выбор прокси в группах, скорость, правила.'),
				row('Состояние', [u.dashState, u.dashLink]),
				row('Действия', u.btnDashInstall))
		]);

		this.refresh();
		addPoll(this.refresh.bind(this), 5);
	},

	refresh: function() {
		var self = this;
		return api('status').then(function(st) { self.update(st || {}); }).catch(function() {});
	},

	update: function(st) {
		var u = this.el;
		var WD = { ok: 'всё в порядке', starting: 'запускаю ядро', waiting_policy: 'жду политику Keenetic',
			paused: 'VPN на паузе', stopped: 'ядро остановлено', error: 'ошибка', down: 'не запущен' };
		u.wdState.textContent = WD[st.state] || st.state || '—';
		u.wdState.className = st.state === 'ok' ? 'ok' : ((st.state === 'error' || st.state === 'down') ? 'bad' : 'warn');
		var warns = st.warnings || [];
		u.warnings.innerHTML = '';
		warns.forEach(function(w) { u.warnings.appendChild(el('div', {}, w)); });
		u.warnings.style.display = warns.length ? '' : 'none';
		u.coreError.textContent = st.core_error ? st.core_error + (st.core_error_log ? '\n\n' + st.core_error_log : '') : '';
		u.coreError.style.display = st.core_error ? '' : 'none';
		this.paused = !!st.paused;
		u.btnPause.textContent = st.paused ? 'Снять паузу' : 'Поставить VPN на паузу';
		u.btnSecureApi.style.display = st.api_open ? '' : 'none';

		u.state.textContent = st.running ? 'запущен' : 'остановлен';
		u.state.className = st.running ? 'ok' : 'bad';

		var details = [];
		if (st.running && st.pid) details.push('PID ' + st.pid);
		if (st.running && st.memory) details.push('память: ' + fmtMem(st.memory));
		u.details.textContent = details.length ? '(' + details.join(', ') + ')' : '';

		u.coreVersion.textContent = st.core_installed
			? (st.core_version || 'неизвестно') + (st.arch ? ' [' + st.arch + ']' : '')
			: 'не установлено';
		u.coreVersion2.textContent = st.core_installed ? (st.core_version || 'неизвестно') : 'не установлено';
		u.panelVersion.textContent = st.panel_version || '—';
		u.autostart.checked = !!st.autostart;
		u.compact.checked = !!st.compact;

		u.btnStart.disabled = !!st.running || !st.core_installed;
		u.btnStop.disabled = !st.running;
		u.btnRestart.disabled = !st.running;
		u.btnCoreUpdate.textContent = st.core_installed ? 'Обновить ядро' : 'Установить ядро';

		u.dashState.textContent = st.dashboard_installed ? 'установлен' : 'не установлен';
		u.dashLink.style.display = (st.dashboard_installed && st.running) ? '' : 'none';
		u.dashLink.href = 'http://' + window.location.hostname + ':' + (st.api_port || '9090') + '/ui/';

		/* Политика */
		var p = st.policy || {};
		if (document.activeElement !== u.policyName)
			u.policyName.value = p.name || 'GrKa';

		u.policyState.innerHTML = '';
		if (p.found) {
			appendAny(u.policyState, [
				el('span', { 'class': 'ok' }, 'политика найдена'),
				el('span', { 'class': 'hint' }, '  (fwmark ' + (p.mark || '?') + ', таблица ' + (p.table || '?') + ')')
			]);
		} else {
			appendAny(u.policyState, [
				el('span', { 'class': 'bad' }, 'политика не найдена'),
				el('span', { 'class': 'hint' }, ' — создайте политику с именем «' + (p.name || 'GrKa') + '» в веб-интерфейсе Keenetic')
			]);
		}

		u.policyRoute.innerHTML = '';
		if (p.route_ok && p.rule_ok) {
			appendAny(u.policyRoute, [
				el('span', { 'class': 'ok' }, 'активна'),
				el('span', { 'class': 'hint' }, '  (клиенты политики → TUN ' + (p.tun || '') + ')')
			]);
		} else if (st.running) {
			appendAny(u.policyRoute, [
				el('span', { 'class': 'warn' }, 'не применена'),
				el('span', { 'class': 'hint' }, p.tun_up
					? ' — нажмите «Применить маршрутизацию»'
					: ' — TUN-интерфейс ' + (p.tun || '') + ' не найден (проверьте tun.device в конфиге)')
			]);
		} else {
			appendAny(u.policyRoute, el('span', { 'class': 'hint' }, st.paused
				? 'VPN на паузе: устройства политики идут напрямую'
				: 'ядро остановлено: у устройств политики нет интернета (без утечек мимо VPN)'));
		}

		u.policyClients.innerHTML = '';
		var cl = p.clients || [];
		if (cl.length)
			cl.forEach(function(name) { u.policyClients.appendChild(el('span', { 'class': 'chip' }, name)); });
		else
			u.policyClients.appendChild(el('span', { 'class': 'hint' }, 'нет клиентов — добавьте устройства в политику на вкладке «Применение политик» в Keenetic'));
	},

	serviceAction: function(action) {
		var self = this;
		return api('service', { action: action }).then(function() { return self.refresh(); });
	},

	checkUpdates: function() {
		var u = this.el;
		return api('check_updates').then(function(res) {
			var coreLatest = res.core_latest || '';
			var panelLatest = res.panel_latest || '';

			u.coreLatest.textContent = coreLatest || 'не удалось получить';
			u.panelLatest.textContent = panelLatest || 'не удалось получить';

			var coreNew = coreLatest && coreLatest !== res.core_current;
			// решает сервер (сравнение версий): у альфы последний стабильный релиз старше, это не обновление
			var panelNew = res.panel_update === true;

			u.coreLatest.className = coreNew ? 'ok' : '';
			u.panelLatest.className = panelNew ? 'ok' : '';
			u.btnPanelUpdate.disabled = !panelNew;
		}).catch(function(e) {
			notify('Ошибка проверки обновлений: ' + e, 'error');
		});
	}
};

/* ---------- Вкладка «Селекторы» ---------- */

var TEST_URL = 'https://www.gstatic.com/generate_204';

var selectorsTab = {
	st: null,
	contentEl: null,

	apiBase: function() {
		return 'http://' + window.location.hostname + ':' + ((this.st && this.st.api_port) || '9090');
	},

	clashApi: function(method, path, body) {
		var headers = {};
		if (this.st && this.st.api_secret)
			headers['Authorization'] = 'Bearer ' + this.st.api_secret;
		return window.fetch(this.apiBase() + path, {
			method: method,
			headers: headers,
			body: body ? JSON.stringify(body) : undefined
		}).then(function(r) {
			if (!r.ok) throw new Error('HTTP ' + r.status);
			return r.json().catch(function() { return null; });
		});
	},

	render: function(root) {
		var self = this;

		this.contentEl = el('div', {}, el('div', { 'class': 'hint' }, 'Загрузка...'));

		var btnRules = el('button', { 'class': 'btn primary', onclick: function() {
			self.updateProviders('rules', 'провайдеров правил');
		} }, 'Обновить провайдеры правил');
		var btnProxies = el('button', { 'class': 'btn primary', onclick: function() {
			self.updateProviders('proxies', 'прокси-провайдеров');
		} }, 'Обновить прокси-провайдеры');
		var btnRefresh = el('button', { 'class': 'btn', onclick: function() { self.refresh(); } }, 'Обновить');

		appendAny(root, [
			el('h2', {}, 'Селекторы'),
			el('div', { 'class': 'descr' },
				'Выбор активного подключения для каждой группы. Клик по карточке — выбрать, ⚡ — замерить задержки группы. Данные из Clash API работающего mihomo.'),
			el('div', { 'class': 'grka-toolbar' }, [btnRules, btnProxies, btnRefresh]),
			this.contentEl
		]);

		this.refresh();
		addPoll(this.refresh.bind(this), 10);
	},

	refresh: function() {
		var self = this;
		return api('status').then(function(st) {
			self.st = st || {};
			if (!self.st.running) return null;
			return self.clashApi('GET', '/proxies').catch(function() { return null; });
		}).then(function(data) {
			self.contentEl.innerHTML = '';
			appendAny(self.contentEl, self.buildContent(data));
		}).catch(function() {});
	},

	chainOf: function(proxies, name) {
		var parts = [], seen = {}, cur = name;
		while (cur && proxies[cur] && proxies[cur].now && !seen[cur]) {
			seen[cur] = true;
			cur = proxies[cur].now;
			parts.push(cur);
		}
		return parts.join(' → ');
	},

	chainEnd: function(proxies, name) {
		var seen = {}, cur = name;
		while (cur && proxies[cur] && proxies[cur].now && !seen[cur]) {
			seen[cur] = true;
			cur = proxies[cur].now;
		}
		return cur;
	},

	lastDelay: function(p) {
		if (p && Array.isArray(p.history) && p.history.length)
			return p.history[p.history.length - 1].delay;
		return null;
	},

	delayBadge: function(d) {
		if (d === null || d === undefined) return el('span', { 'class': 'd-na' }, '—');
		if (!d) return el('span', { 'class': 'd-bad' }, 'timeout');
		var cls = d < 200 ? 'd-ok' : (d < 500 ? 'd-mid' : 'd-bad');
		return el('span', { 'class': cls }, d + ' ms');
	},

	selectProxy: function(group, name) {
		var self = this;
		return this.clashApi('PUT', '/proxies/' + encodeURIComponent(group), { name: name }).then(function() {
			return self.refresh();
		}).catch(function(e) {
			notify('Не удалось выбрать прокси: ' + e, 'error');
		});
	},

	testGroup: function(group, btn) {
		var self = this;
		btn.textContent = '…';
		btn.disabled = true;
		return this.clashApi('GET', '/group/' + encodeURIComponent(group) + '/delay?url=' +
			encodeURIComponent(TEST_URL) + '&timeout=5000').catch(function() {}).then(function() {
			return self.refresh();
		});
	},

	updateProviders: function(kind, label) {
		var self = this;
		return this.clashApi('GET', '/providers/' + kind).then(function(d) {
			var provs = (d && d.providers) || {};
			var names = Object.keys(provs).filter(function(n) {
				return provs[n].vehicleType === 'HTTP';
			});
			if (!names.length) {
				notify('Нет загружаемых (HTTP) ' + label + ' для обновления');
				return;
			}
			var failed = [];
			return Promise.all(names.map(function(n) {
				return self.clashApi('PUT', '/providers/' + kind + '/' + encodeURIComponent(n)).catch(function() {
					failed.push(n);
				});
			})).then(function() {
				var msg = 'Обновлено ' + (names.length - failed.length) + ' из ' + names.length + ' ' + label;
				if (failed.length) msg += '. Ошибки: ' + failed.join(', ');
				notify(msg, failed.length ? 'error' : 'info');
			});
		}).catch(function(e) {
			notify('Ошибка запроса к Clash API: ' + e, 'error');
		});
	},

	buildContent: function(data) {
		var self = this;

		if (!this.st || !this.st.running)
			return [el('div', { 'class': 'section warn' },
				'Сервис mihomo не запущен. Запустите его на вкладке «Статус» — селекторы работают через Clash API работающего mihomo.')];

		if (!data || !data.proxies)
			return [el('div', { 'class': 'section' }, [
				el('p', { 'style': 'margin-top:0' }, 'Clash API недоступен (' + this.apiBase() + '). Проверьте:'),
				el('ul', { 'style': 'margin:0;padding-left:1.4em', 'class': 'hint' }, [
					el('li', {}, 'в конфиге задано external-controller: 0.0.0.0:9090'),
					el('li', {}, 'mihomo перезапущен после изменения конфига'),
					el('li', {}, 'страница открыта по http (не https), иначе браузер блокирует запросы')
				])
			])];

		var proxies = data.proxies;
		var order = (proxies.GLOBAL && Array.isArray(proxies.GLOBAL.all)) ? proxies.GLOBAL.all : Object.keys(proxies);
		var groups = order.filter(function(n) {
			var p = proxies[n];
			return p && p.type === 'Selector' && Array.isArray(p.all) && n !== 'GLOBAL';
		});

		if (!groups.length)
			return [el('div', { 'class': 'section' },
				'В конфигурации нет групп типа select. Добавьте proxy-groups (например, через шаблон «Сервисы и селекторы» на вкладке «Конфигурация»).')];

		return groups.map(function(gname) {
			var g = proxies[gname];
			var testBtn = el('button', { 'class': 'btn', title: 'Замерить задержки' }, '⚡');
			testBtn.onclick = function() { self.testGroup(gname, testBtn); };

			var cards = g.all.map(function(pname) {
				var p = proxies[pname] || {};
				var isGroup = Array.isArray(p.all);
				var sub = (p.type || '').toLowerCase() + (p.udp ? ' / udp' : '');
				var card = el('div', {
					'class': 'grka-proxy' + (g.now === pname ? ' active' : ''),
					title: isGroup ? 'Группа' : 'Прокси'
				},
					el('div', { 'class': 'pname' }, pname),
					el('div', { 'class': 'sub' },
						el('span', {}, sub),
						self.delayBadge(isGroup ? self.lastDelay(proxies[self.chainEnd(proxies, pname)]) : self.lastDelay(p))));
				card.onclick = function() { self.selectProxy(gname, pname); };
				return card;
			});

			var head = [];
			if (g.icon)
				head.push(el('img', { src: g.icon, onerror: function(ev) { ev.target.style.display = 'none'; } }));
			head.push(el('h3', {}, gname));
			head.push(el('span', { 'class': 'spacer' }));
			head.push(testBtn);

			return el('div', { 'class': 'grka-group' },
				el('div', { 'class': 'grka-ghead' }, head),
				el('div', { 'class': 'grka-chain' }, 'Selector (' + g.all.length + ') → ' + (self.chainOf(proxies, gname) || '—')),
				el('div', { 'class': 'grka-plist' }, cards));
		});
	}
};

/* ---------- Парсер прокси-ссылок -> объект прокси mihomo ---------- */

function b64decode(s) {
	s = s.replace(/-/g, '+').replace(/_/g, '/').replace(/\s+/g, '');
	while (s.length % 4) s += '=';
	return decodeURIComponent(escape(window.atob(s)));
}

function parseQuery(q) {
	var out = {};
	(q || '').split('&').forEach(function(kv) {
		if (!kv) return;
		var i = kv.indexOf('=');
		var k = i < 0 ? kv : kv.slice(0, i);
		var v = i < 0 ? '' : kv.slice(i + 1);
		try { out[k] = decodeURIComponent(v.replace(/\+/g, '%20')); }
		catch (e) { out[k] = v; }
	});
	return out;
}

function parseUri(link) {
	var m = link.match(/^([a-z0-9]+):\/\/([^#]+)(?:#(.*))?$/i);
	if (!m) return null;
	var scheme = m[1].toLowerCase();
	var body = m[2];
	var name = '';
	try { name = m[3] ? decodeURIComponent(m[3]) : ''; }
	catch (e) { name = m[3] || ''; }

	var userinfo = null;
	var at = body.lastIndexOf('@');
	if (at >= 0) {
		userinfo = body.slice(0, at);
		body = body.slice(at + 1);
	}

	var query = '';
	var qi = body.indexOf('?');
	if (qi >= 0) {
		query = body.slice(qi + 1);
		body = body.slice(0, qi);
	}
	body = body.replace(/\/+$/, '').replace(/\/.*$/, '');

	var host = body, port = '';
	var pm = body.match(/^(\[[^\]]+\]|[^:]+):(\d+)$/);
	if (pm) {
		host = pm[1].replace(/^\[|\]$/g, '');
		port = pm[2];
	}

	return {
		scheme: scheme,
		userinfo: userinfo,
		host: host,
		port: parseInt(port, 10) || 443,
		q: parseQuery(query),
		name: name
	};
}

function applyNetwork(p, net, u) {
	var q = u.q;
	net = net || 'tcp';
	if (net === 'tcp' || net === 'raw') return;
	p.network = net;
	if (net === 'ws') {
		p['ws-opts'] = { path: q.path || '/' };
		if (q.host) p['ws-opts'].headers = { Host: q.host };
	} else if (net === 'grpc') {
		p['grpc-opts'] = { 'grpc-service-name': q.serviceName || q.path || '' };
	} else if (net === 'http' || net === 'h2') {
		p.network = 'h2';
		p['h2-opts'] = { path: q.path || '/' };
		if (q.host) p['h2-opts'].host = [q.host];
	}
}

function parseProxyLink(link) {
	link = (link || '').trim();
	var u;

	if (/^vmess:\/\//i.test(link)) {
		var v = JSON.parse(b64decode(link.slice(8)));
		var p = {
			name: v.ps || (v.add + ':' + v.port),
			type: 'vmess',
			server: v.add,
			port: parseInt(v.port, 10),
			uuid: v.id,
			alterId: parseInt(v.aid, 10) || 0,
			cipher: v.scy || 'auto',
			udp: true
		};
		if (v.tls === 'tls' || v.tls === true) {
			p.tls = true;
			if (v.sni || v.host) p.servername = v.sni || v.host;
		}
		var net = v.net || 'tcp';
		if (net !== 'tcp') {
			p.network = net;
			if (net === 'ws') {
				p['ws-opts'] = { path: v.path || '/' };
				if (v.host) p['ws-opts'].headers = { Host: v.host };
			} else if (net === 'grpc') {
				p['grpc-opts'] = { 'grpc-service-name': v.path || '' };
			}
		}
		return p;
	}

	u = parseUri(link);
	if (!u) throw new Error('Не удалось разобрать ссылку');

	if (u.scheme === 'vless') {
		var q = u.q;
		var p2 = {
			name: u.name || (u.host + ':' + u.port),
			type: 'vless',
			server: u.host,
			port: u.port,
			uuid: u.userinfo,
			udp: true
		};
		if (q.flow) p2.flow = q.flow;
		if (q.security === 'tls' || q.security === 'reality') {
			p2.tls = true;
			if (q.sni) p2.servername = q.sni;
			p2['client-fingerprint'] = q.fp || 'chrome';
		}
		if (q.security === 'reality') {
			p2['reality-opts'] = { 'public-key': q.pbk || '' };
			if (q.sid) p2['reality-opts']['short-id'] = q.sid;
		}
		if (q.alpn) p2.alpn = q.alpn.split(',');
		applyNetwork(p2, q.type, u);
		return p2;
	}

	if (u.scheme === 'trojan') {
		var q3 = u.q;
		var p3 = {
			name: u.name || (u.host + ':' + u.port),
			type: 'trojan',
			server: u.host,
			port: u.port,
			password: u.userinfo,
			udp: true
		};
		if (q3.sni) p3.sni = q3.sni;
		if (q3.allowInsecure === '1' || q3.insecure === '1') p3['skip-cert-verify'] = true;
		if (q3.fp) p3['client-fingerprint'] = q3.fp;
		applyNetwork(p3, q3.type, u);
		return p3;
	}

	if (u.scheme === 'ss') {
		var method, password, host = u.host, port = u.port, name = u.name;
		if (u.userinfo !== null) {
			var creds;
			try {
				creds = b64decode(u.userinfo);
				if (creds.indexOf(':') < 0) throw new Error('no colon');
			} catch (e) {
				try { creds = decodeURIComponent(u.userinfo); }
				catch (e2) { creds = u.userinfo; }
			}
			var ci = creds.indexOf(':');
			method = creds.slice(0, ci);
			password = creds.slice(ci + 1);
		} else {
			var full = b64decode(link.slice(5).split('#')[0]);
			var fm = full.match(/^(.+?):(.+)@(.+):(\d+)$/);
			if (!fm) throw new Error('Не удалось разобрать ss-ссылку');
			method = fm[1];
			password = fm[2];
			host = fm[3];
			port = parseInt(fm[4], 10);
		}
		return {
			name: name || (host + ':' + port),
			type: 'ss',
			server: host,
			port: port,
			cipher: method,
			password: password,
			udp: true
		};
	}

	if (u.scheme === 'hysteria2' || u.scheme === 'hy2') {
		var q4 = u.q;
		var p4 = {
			name: u.name || (u.host + ':' + u.port),
			type: 'hysteria2',
			server: u.host,
			port: u.port,
			password: u.userinfo || ''
		};
		if (q4.sni) p4.sni = q4.sni;
		if (q4.insecure === '1') p4['skip-cert-verify'] = true;
		if (q4.obfs) p4.obfs = q4.obfs;
		if (q4['obfs-password']) p4['obfs-password'] = q4['obfs-password'];
		return p4;
	}

	if (u.scheme === 'tuic') {
		var q5 = u.q;
		var creds5 = (u.userinfo || '').split(':');
		var p5 = {
			name: u.name || (u.host + ':' + u.port),
			type: 'tuic',
			server: u.host,
			port: u.port,
			uuid: creds5[0] || '',
			password: creds5[1] || ''
		};
		if (q5.sni) p5.sni = q5.sni;
		if (q5.congestion_control) p5['congestion-controller'] = q5.congestion_control;
		if (q5.alpn) p5.alpn = q5.alpn.split(',');
		return p5;
	}

	throw new Error('Схема «' + u.scheme + '://» не поддерживается. Поддерживаются: vless, vmess, trojan, ss, hysteria2, tuic');
}

/* JSON — подмножество YAML, поэтому объект прокси можно вставить как flow-map */
function proxyToYaml(p) {
	return '  - ' + JSON.stringify(p);
}

function insertProxyIntoConfig(cfg, yamlLine) {
	var emptyRe = /^proxies:[ \t]*\[\][ \t]*$/m;
	if (emptyRe.test(cfg))
		return cfg.replace(emptyRe, 'proxies:\n' + yamlLine);

	var m = cfg.match(/^proxies:[ \t]*$/m);
	if (m) {
		var idx = m.index + m[0].length;
		return cfg.slice(0, idx) + '\n' + yamlLine + cfg.slice(idx);
	}
	return cfg.replace(/\s*$/, '') + '\n\nproxies:\n' + yamlLine + '\n';
}

/* ---------- Вкладка «Конфигурация» ---------- */

var configTab = {
	textarea: null,

	render: function(root) {
		var self = this;

		this.textarea = el('textarea', {
			'class': 'editor',
			spellcheck: 'false',
			wrap: 'off',
			onkeydown: function(ev) {
				if (ev.key === 'Tab') {
					ev.preventDefault();
					var t = ev.target;
					var s = t.selectionStart, e = t.selectionEnd;
					t.value = t.value.slice(0, s) + '  ' + t.value.slice(e);
					t.selectionStart = t.selectionEnd = s + 2;
				}
			}
		});

		appendAny(root, [
			el('h2', {}, 'Конфигурация mihomo'),
			el('div', { 'class': 'descr' }, [
				'Файл ', el('code', {}, '/opt/etc/mihomo/config.yaml'),
				'. Перед сохранением с перезапуском конфигурация автоматически проверяется.'
			]),
			el('div', { 'class': 'section' }, [
				el('div', { 'class': 'btnrow', 'style': 'margin-bottom:.6em' }, [
					el('button', { 'class': 'btn primary', onclick: function() { self.addProxyModal(); } }, 'Добавить прокси из ссылки'),
					el('button', { 'class': 'btn', onclick: function() { self.templatesModal(); } }, 'Шаблоны'),
					el('button', { 'class': 'btn', onclick: function() { self.backupsModal(); } }, 'Бэкапы')
				]),
				this.textarea,
				el('div', { 'class': 'btnrow', 'style': 'margin-top:.6em' }, [
					el('button', { 'class': 'btn', onclick: function() { self.check(); } }, 'Проверить'),
					el('button', { 'class': 'btn primary', onclick: function() { self.save(false); } }, 'Сохранить'),
					el('button', { 'class': 'btn green', onclick: function() { self.saveRestart(); } }, 'Сохранить и перезапустить')
				])
			])
		]);

		api('get_config').then(function(r) {
			self.textarea.value = (r && r.content) || '';
		}).catch(function() {});
	},

	check: function() {
		return api('check_config', { content: this.textarea.value }).then(function(res) {
			modal(res.ok ? '✅ Конфигурация корректна' : '❌ Ошибка в конфигурации',
				[el('pre', { 'class': 'term', 'style': 'max-height:50vh' }, res.output || '')],
				[el('button', { 'class': 'btn', onclick: closeModal }, 'Закрыть')]);
		});
	},

	save: function(restart) {
		return api('set_config', { content: this.textarea.value }).then(function(res) {
			if (!res || !res.ok) {
				modal('❌ Конфигурация не сохранена', [
					el('p', {}, (res && res.error) || 'Ошибка сохранения'),
					res && res.output ? el('pre', { 'class': 'term', 'style': 'max-height:50vh' }, res.output) : null
				], [el('button', { 'class': 'btn', onclick: closeModal }, 'Закрыть')]);
				return false;
			}
			if (res.warning) notify(res.warning, 'error');
			if (restart) return api('service', { action: 'restart' }).then(function() { return true; });
			return true;
		}).then(function(saved) {
			if (saved) notify(restart ? 'Конфигурация сохранена, ядро перезапускается' : 'Конфигурация сохранена');
		});
	},

	saveRestart: function() {
		var self = this;
		return api('check_config', { content: this.textarea.value }).then(function(res) {
			if (!res.ok) {
				modal('❌ Конфигурация не прошла проверку — не сохранено',
					[el('pre', { 'class': 'term', 'style': 'max-height:50vh' }, res.output || '')],
					[el('button', { 'class': 'btn', onclick: closeModal }, 'Закрыть')]);
				return;
			}
			return self.save(true);
		});
	},

	backupsModal: function() {
		var self = this;
		return api('list_backups').then(function(res) {
			var backups = (res && res.backups) || [];
			var rows = backups.map(function(name) {
				return el('div', { 'class': 'list-row' },
					el('code', {}, name),
					el('button', { 'class': 'btn primary', onclick: function() {
						api('restore_backup', { name: name }).then(function(r) {
							if (r && r.ok) {
								closeModal();
								return api('get_config').then(function(cfg) {
									self.textarea.value = cfg.content || '';
									notify('Бэкап восстановлен (перезапустите mihomo для применения)');
								});
							}
							notify((r && r.error) || 'Ошибка восстановления', 'error');
						});
					} }, 'Восстановить'));
			});
			modal('Бэкапы конфигурации', [
				el('div', { 'class': 'descr' }, 'Бэкап создаётся автоматически при каждом сохранении (хранятся последние 10).'),
				rows.length ? el('div', {}, rows) : el('p', {}, 'Бэкапов пока нет')
			], [el('button', { 'class': 'btn', onclick: closeModal }, 'Закрыть')]);
		});
	},

	templatesModal: function() {
		var self = this;
		return api('list_templates').then(function(res) {
			var templates = (res && res.templates) || [];
			var rows = templates.map(function(t) {
				return el('div', { 'class': 'list-row' },
					el('span', {}, t.title || t.id),
					el('button', { 'class': 'btn primary', onclick: function() {
						api('get_template', { id: t.id }).then(function(r) {
							if (!r || !r.ok) {
								notify((r && r.error) || 'Не удалось загрузить шаблон', 'error');
								return;
							}
							if (self.textarea.value.trim() &&
								!window.confirm('Заменить текущее содержимое редактора шаблоном «' + (t.title || t.id) + '»? (На роутере ничего не изменится, пока вы не нажмёте «Сохранить».)'))
								return;
							self.textarea.value = r.content || '';
							closeModal();
							notify('Шаблон загружен в редактор. Добавьте прокси и сохраните конфигурацию.');
						});
					} }, 'Загрузить'));
			});
			modal('Шаблоны конфигураций', [
				el('div', { 'class': 'descr' }, 'Готовые конфигурации mihomo. Шаблон загружается в редактор — на роутер он попадёт только после нажатия «Сохранить».'),
				rows.length ? el('div', {}, rows) : el('p', {}, 'Шаблоны не найдены')
			], [el('button', { 'class': 'btn', onclick: closeModal }, 'Закрыть')]);
		});
	},

	addProxyModal: function() {
		var self = this;
		var input = el('input', { type: 'text', 'style': 'width:100%',
			placeholder: 'vless:// vmess:// trojan:// ss:// hysteria2:// tuic://' });
		var preview = el('pre', { 'class': 'term', 'style': 'max-height:30vh;display:none;margin-top:.6em' }, '');
		var errBox = el('p', { 'style': 'color:var(--red);display:none;margin:.5em 0 0' }, '');
		var btnInsert = el('button', { 'class': 'btn green', disabled: true }, 'Вставить в конфиг');
		var generated = null;

		var btnGen = el('button', { 'class': 'btn primary', onclick: function() {
			errBox.style.display = 'none';
			preview.style.display = 'none';
			generated = null;
			btnInsert.disabled = true;
			try {
				var p = parseProxyLink(input.value);
				generated = proxyToYaml(p);
				preview.textContent = generated;
				preview.style.display = '';
				btnInsert.disabled = false;
			} catch (e) {
				errBox.textContent = 'Ошибка: ' + (e.message || e);
				errBox.style.display = '';
			}
		} }, 'Сгенерировать');

		btnInsert.onclick = function() {
			if (!generated) return;
			self.textarea.value = insertProxyIntoConfig(self.textarea.value, generated);
			closeModal();
			notify('Прокси добавлен в раздел proxies. Не забудьте прописать его имя в proxy-groups/rules и сохранить конфиг.');
		};

		modal('Добавить прокси из ссылки', [
			el('p', { 'style': 'margin-top:0' }, 'Вставьте ссылку на прокси — она будет преобразована в формат mihomo:'),
			input, errBox, preview
		], [
			el('button', { 'class': 'btn', onclick: closeModal }, 'Отмена'),
			btnGen, btnInsert
		]);
		input.focus();
	}
};

/* ---------- Вкладка «Логи» ---------- */

var logsTab = {
	raw: '',
	paused: false,

	render: function(root) {
		var self = this;
		this.raw = '';
		this.paused = false;

		this.pre = el('pre', { 'class': 'term', 'style': 'height:65vh' }, '');

		this.filterInput = el('input', { type: 'text', 'style': 'width:20em',
			placeholder: 'Фильтр (например: error, warning, dns)...',
			oninput: function() { self.applyFilter(); } });

		this.linesSelect = el('select', {},
			el('option', { value: '100' }, '100 строк'),
			el('option', { value: '200', selected: 'selected' }, '200 строк'),
			el('option', { value: '500' }, '500 строк'),
			el('option', { value: '1000' }, '1000 строк'));

		this.autoscroll = el('input', { type: 'checkbox', checked: true });

		this.sourceSelect = el('select', { onchange: function() { self.fetchLog(); } },
			el('option', { value: 'journal' }, 'Журнал сторожа'),
			el('option', { value: 'core' }, 'Лог ядра'));

		var pauseBtn = el('button', { 'class': 'btn', onclick: function(ev) {
			self.paused = !self.paused;
			ev.target.textContent = self.paused ? 'Продолжить' : 'Пауза';
		} }, 'Пауза');

		appendAny(root, [
			el('h2', {}, 'Логи mihomo'),
			el('div', { 'class': 'descr' }, 'Журнал сторожа (что он проверял и чинил) и лог ядра (в памяти роутера, ротация при 1 МБ). Автообновление каждые 3 секунды.'),
			el('div', { 'class': 'section' }, [
				el('div', { 'class': 'btnrow', 'style': 'margin-bottom:.6em' }, [
					this.sourceSelect,
					this.filterInput,
					this.linesSelect,
					pauseBtn,
					el('label', { 'style': 'margin-left:.6em' }, [this.autoscroll, ' автопрокрутка'])
				]),
				this.pre
			])
		]);

		this.fetchLog();
		addPoll(this.fetchLog.bind(this), 3);
	},

	applyFilter: function() {
		var filter = (this.filterInput.value || '').toLowerCase();
		var text = this.raw;
		if (filter) {
			text = text.split('\n').filter(function(line) {
				return line.toLowerCase().indexOf(filter) >= 0;
			}).join('\n');
		}
		this.pre.textContent = text || '(пусто)';
		if (this.autoscroll.checked)
			this.pre.scrollTop = this.pre.scrollHeight;
	},

	fetchLog: function() {
		var self = this;
		if (this.paused) return Promise.resolve();
		return api('get_log', { lines: parseInt(this.linesSelect.value, 10), source: this.sourceSelect.value }).then(function(res) {
			self.raw = (res && res.log) || '';
			self.applyFilter();
		}).catch(function() {});
	}
};

/* ---------- Запуск ---------- */

var TABS = {
	status: statusTab,
	selectors: selectorsTab,
	config: configTab,
	logs: logsTab
};

function updateTopState() {
	api('status').then(function(st) {
		var t = document.getElementById('top-state');
		t.innerHTML = '';
		appendAny(t, ['mihomo: ', el('b', { 'class': st.running ? 'on' : 'off' }, st.running ? 'запущен' : 'остановлен'),
			st.panel_version ? '  ·  v' + st.panel_version : '']);
	}).catch(function() {});
}

document.addEventListener('DOMContentLoaded', function() {
	document.querySelectorAll('.tabs button').forEach(function(b) {
		b.onclick = function() { showTab(b.getAttribute('data-tab')); };
	});

	var params = new URLSearchParams(window.location.search);
	showTab(TABS[params.get('tab')] ? params.get('tab') : 'status');

	updateTopState();
	window.setInterval(updateTopState, 5000);
});

/* для демо-режима и отладки */
window.GrKa = { showTab: showTab, api: api };
