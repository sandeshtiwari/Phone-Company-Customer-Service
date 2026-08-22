const shell = document.querySelector('.shell');
const loginForm = document.querySelector('#login-form');
const experience = document.querySelector('#experience');
const chatForm = document.querySelector('#chat-form');
const messages = document.querySelector('#messages');
const messageInput = document.querySelector('#message');
const sendButton = document.querySelector('#send-button');
const traceEmpty = document.querySelector('#trace-empty');
const traceLoading = document.querySelector('#trace-loading');
const traceLive = document.querySelector('#trace-live');
const traceContent = document.querySelector('#trace-content');
const traceSelector = document.querySelector('#trace-selector');
const traceSections = document.querySelector('#trace-sections');
const liveMode = document.querySelector('#live-mode');
const liveTitle = document.querySelector('#live-title');
const liveSubtitle = document.querySelector('#live-subtitle');
const liveLane = document.querySelector('#live-lane');
const liveEvents = document.querySelector('#live-events');
const liveDetails = document.querySelector('#live-details');
const sequenceNav = document.querySelector('#sequence-nav');
const sequencePrev = document.querySelector('#sequence-prev');
const sequenceNext = document.querySelector('#sequence-next');
const sequencePosition = document.querySelector('#sequence-position');
const toast = document.querySelector('#toast');

let chatSessionId = sessionStorage.getItem('chatSessionId');
let traceHistory = [];
let activeTraceId = null;
let toastTimer;
let playbackId = 0;
let selectedLiveIndex = -1;
let liveRenderedEvents = [];
let autoFollowLiveEvents = true;

function showToast(message) {
  toast.textContent = message;
  toast.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove('show'), 1800);
}

function addMessage(role, text, options = {}) {
  const node = document.createElement('article');
  node.className = `message ${role}${options.pending ? ' pending' : ''}`;
  const avatar = document.createElement('div');
  avatar.className = 'message-avatar';
  avatar.setAttribute('aria-hidden', 'true');
  avatar.textContent = role === 'user' ? 'Y' : 'L';
  const stack = document.createElement('div');
  stack.className = 'message-stack';
  const label = document.createElement('div');
  label.className = 'message-label';
  label.textContent = role === 'user' ? 'You' : 'Luna Care';
  const bubble = document.createElement('div');
  bubble.className = 'bubble';
  if (options.pending) {
    bubble.innerHTML = '<span class="typing-dots" aria-label="Working"><i></i><i></i><i></i></span>';
  } else if (role === 'assistant') {
    bubble.innerHTML = renderAssistantText(text);
  } else {
    bubble.textContent = text;
  }
  stack.append(label, bubble);
  if (options.trace) {
    const meta = document.createElement('div');
    meta.className = 'message-meta';
    const calls = options.trace.summary?.runner_calls || 0;
    const inspect = document.createElement('button');
    inspect.type = 'button';
    inspect.className = 'inspect-trace';
    inspect.textContent = calls === 1 ? 'View 1 Runner call' : `View ${calls} Runner calls`;
    inspect.addEventListener('click', () => selectTrace(options.trace.trace_id, true));
    meta.append(inspect, document.createTextNode(`· ${formatDuration(options.trace.duration_ms)}`));
    stack.append(meta);
  }
  node.append(avatar, stack);
  messages.append(node);
  messages.scrollTop = messages.scrollHeight;
  return node;
}

function proposalIdsFromAnswer(text) {
  return [...new Set(String(text).match(/\bwrp_[A-Za-z0-9_-]{8,80}\b/g) || [])];
}

function proposalStatusView(status) {
  const state = status.status || 'unknown';
  if (state === 'applied' && status.source_database_changed) {
    const receipt = status.receipt || {};
    const version = receipt.previous_version && receipt.new_version
      ? ` · version ${receipt.previous_version} → ${receipt.new_version}`
      : '';
    return {tone:'applied', title:'Applied to your account', detail:`Trusted writeback completed${version}.`, terminal:true};
  }
  if (['approved', 'pending_worker', 'queued'].includes(state)) {
    return {tone:'waiting', title:'Approved · applying automatically', detail:'The trusted app worker is processing this change.', terminal:false};
  }
  if (['conflict', 'failed', 'rejected', 'cancelled', 'expired'].includes(state)) {
    return {tone:'failed', title:`Not applied · ${state.replace('_', ' ')}`, detail:'Your account was not changed. Ask Luna to inspect the setting before retrying.', terminal:true};
  }
  return {tone:'review', title:'Awaiting reviewed approval', detail:'This proposal has not changed the account yet.', terminal:false};
}

async function trackProposal(messageNode, proposalId) {
  const tracker = document.createElement('div');
  tracker.className = 'proposal-status waiting';
  tracker.innerHTML = `<span class="proposal-status-dot"></span><div><strong>Checking automatic application…</strong><small>${escapeHtml(proposalId)}</small></div>`;
  messageNode.querySelector('.message-stack').append(tracker);
  for (let attempt = 0; attempt < 30; attempt += 1) {
    try {
      const response = await fetch(`/api/proposals/${encodeURIComponent(proposalId)}`, {credentials:'same-origin',cache:'no-store'});
      if (response.ok) {
        const status = await response.json();
        const view = proposalStatusView(status);
        tracker.className = `proposal-status ${view.tone}`;
        tracker.querySelector('strong').textContent = view.title;
        tracker.querySelector('small').textContent = `${view.detail} · ${proposalId}`;
        messages.scrollTop = messages.scrollHeight;
        if (view.terminal) return;
      } else if (response.status === 401) {
        tracker.className = 'proposal-status failed';
        tracker.querySelector('strong').textContent = 'Session expired before status confirmation';
        return;
      }
    } catch {
      // A transient status read must not interrupt chat or hide the proposal id.
    }
    await wait(2000);
  }
  tracker.className = 'proposal-status waiting';
  tracker.querySelector('strong').textContent = 'Approved · background application still pending';
  tracker.querySelector('small').textContent = `You can keep chatting while the trusted worker continues · ${proposalId}`;
}

function trackProposals(messageNode, answer) {
  proposalIdsFromAnswer(answer).forEach((proposalId) => {
    trackProposal(messageNode, proposalId);
  });
}

function formatDuration(value) {
  if (!Number.isFinite(value)) return '—';
  if (value < 1000) return `${value} ms`;
  return `${(value / 1000).toFixed(value < 10000 ? 1 : 0)} s`;
}

function shorten(text, length = 58) {
  if (!text) return 'Untitled request';
  return text.length > length ? `${text.slice(0, length - 1)}…` : text;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function renderAssistantText(value) {
  return escapeHtml(value)
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/\n/g, '<br>');
}

function syntaxHighlight(value) {
  const serialized = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
  const safe = escapeHtml(serialized ?? 'null');
  return safe.replace(/(&quot;(?:\\u[a-fA-F0-9]{4}|\\[^u]|[^\\&])*&quot;\s*:|&quot;(?:\\u[a-fA-F0-9]{4}|\\[^u]|[^\\&])*&quot;|\btrue\b|\bfalse\b|\bnull\b|-?\d+(?:\.\d+)?(?:[eE][+\-]?\d+)?)/g, (match) => {
    let tokenClass = 'json-number';
    if (match.startsWith('&quot;')) tokenClass = match.trimEnd().endsWith(':') ? 'json-key' : 'json-string';
    else if (match === 'true' || match === 'false') tokenClass = 'json-boolean';
    else if (match === 'null') tokenClass = 'json-null';
    return `<span class="${tokenClass}">${match}</span>`;
  });
}

function codeViewer(label, value, language = 'json', options = {}) {
  const shellNode = document.createElement('div');
  shellNode.className = 'code-shell';
  const head = document.createElement('div');
  head.className = 'code-head';
  const title = document.createElement('span');
  title.textContent = label;
  const copy = document.createElement('button');
  copy.type = 'button';
  copy.className = 'code-copy';
  copy.textContent = 'Copy';
  const raw = (typeof value === 'string' ? value : JSON.stringify(value, null, 2)) ?? 'null';
  const previewLimit = options.previewLimit ?? 30000;
  const truncated = raw.length > previewLimit;
  copy.addEventListener('click', async () => {
    await navigator.clipboard.writeText(raw ?? '');
    copy.textContent = 'Copied';
    showToast(`${label} copied`);
    setTimeout(() => { copy.textContent = 'Copy'; }, 1200);
  });
  const actions = document.createElement('div');
  actions.className = 'code-actions';
  let expand = null;
  if (truncated) {
    expand = document.createElement('button');
    expand.type = 'button';
    expand.className = 'code-expand';
    expand.textContent = 'Show full JSON';
    actions.append(expand);
  }
  actions.append(copy);
  head.append(title, actions);
  const pre = document.createElement('pre');
  const code = document.createElement('code');
  const renderCode = (full) => {
    const visible = full || !truncated
      ? raw
      : `${raw.slice(0, previewLimit)}\n\n… ${raw.length - previewLimit} characters hidden; use Show full JSON …`;
    if (language === 'json') code.innerHTML = syntaxHighlight(visible);
    else { code.className = 'prompt-code'; code.textContent = visible || '(none)'; }
  };
  renderCode(false);
  expand?.addEventListener('click', () => {
    expand.disabled = true;
    expand.textContent = 'Rendering…';
    requestAnimationFrame(() => requestAnimationFrame(() => {
      renderCode(true);
      expand.remove();
      shellNode.classList.add('expanded');
    }));
  });
  pre.append(code);
  shellNode.append(head, pre);
  return shellNode;
}

function detailGroup(icon, iconClass, title, subtitle, count, open = false) {
  const details = document.createElement('details');
  details.className = 'trace-group';
  details.open = open;
  const summary = document.createElement('summary');
  summary.innerHTML = `<span class="group-icon ${iconClass}">${escapeHtml(icon)}</span><span class="group-heading"><strong>${escapeHtml(title)}</strong><small>${escapeHtml(subtitle)}</small></span>${count == null ? '' : `<span class="group-count">${count}</span>`}`;
  const body = document.createElement('div');
  body.className = 'trace-group-body';
  details.append(summary, body);
  return {details, body};
}

function renderCatalogs(trace) {
  const catalogs = trace.tool_catalogs || [];
  const toolCount = catalogs.reduce((sum, item) => sum + (item.tools?.length || 0), 0);
  const group = detailGroup('⌘', 'catalog', 'Tool catalog shown to the model', `${catalogs.length} MCP surfaces · click a tool to inspect its schema`, toolCount);
  catalogs.forEach((catalog) => {
    const section = document.createElement('section');
    section.className = 'catalog-server';
    const heading = document.createElement('p');
    heading.textContent = `${catalog.server} · ${catalog.transport}`;
    const grid = document.createElement('div');
    grid.className = 'tool-pill-grid';
    (catalog.tools || []).forEach((tool) => {
      const pill = document.createElement('button');
      pill.type = 'button';
      pill.className = `tool-pill${tool.model_tool_name !== tool.runner_tool_name ? ' alias' : ''}`;
      pill.textContent = tool.model_tool_name;
      pill.title = tool.description || tool.runner_tool_name;
      pill.addEventListener('click', () => {
        section.querySelector('.catalog-schema')?.remove();
        const schema = codeViewer(`${tool.runner_tool_name} input schema`, tool.input_schema || {});
        schema.classList.add('catalog-schema');
        section.append(schema);
      });
      grid.append(pill);
    });
    section.append(heading, grid);
    group.body.append(section);
  });
  return group.details;
}

function renderModelTurns(trace) {
  const turns = trace.model_turns || [];
  const group = detailGroup('AI', 'model', 'What the model saw', 'System instructions, conversation items, and prior tool results', turns.length, true);
  turns.forEach((turn, index) => {
    const section = document.createElement('section');
    section.className = 'model-turn';
    const heading = document.createElement('p');
    heading.className = 'subheading';
    const title = document.createElement('strong');
    title.textContent = `Model turn ${turn.turn || index + 1}`;
    const model = document.createElement('span');
    model.textContent = trace.model;
    heading.append(title, model);
    section.append(heading);
    if (index === 0) section.append(codeViewer('System instructions', turn.system_prompt, 'text'));
    section.append(codeViewer('Input items sent to model', turn.input_items || []));
    if (turn.model_output) section.append(codeViewer('Raw model output', turn.model_output));
    group.body.append(section);
  });
  return group.details;
}

function renderRunnerCalls(trace) {
  const calls = trace.runner_calls || [];
  const group = detailGroup('↔', 'call', 'Model ↔ Runner calls', 'Exact MCP arguments, canonical names, and scoped return payloads', calls.length, true);
  if (!calls.length) {
    const empty = document.createElement('p');
    empty.className = 'no-calls';
    empty.textContent = 'This interaction completed without a Runner tool call. Inspect the model turns below to see what context produced the response.';
    group.body.append(empty);
    return group.details;
  }
  calls.forEach((call) => {
    const card = document.createElement('article');
    card.className = 'call-card';
    const header = document.createElement('div');
    header.className = 'call-card-header';
    const sequence = document.createElement('span'); sequence.className = 'call-sequence'; sequence.textContent = `#${call.sequence}`;
    const name = document.createElement('span'); name.className = 'call-name'; name.textContent = call.runner_request?.name || 'unknown';
    const status = document.createElement('span'); status.className = `status ${call.status === 'ok' ? 'ok' : 'error'}`; status.textContent = call.status;
    const duration = document.createElement('span'); duration.className = 'call-duration'; duration.textContent = formatDuration(call.duration_ms);
    header.append(sequence, name, status, duration);
    const flow = document.createElement('div');
    flow.className = 'call-flow';

    const modelStage = document.createElement('section');
    modelStage.className = 'flow-stage model-stage';
    modelStage.innerHTML = '<div class="flow-label"><i></i>1 · Model emitted</div>';
    const aliasMap = document.createElement('div');
    aliasMap.className = 'alias-map';
    const modelName = document.createElement('code'); modelName.textContent = call.model_emitted?.name || 'unknown';
    const arrow = document.createElement('b'); arrow.textContent = '→ alias map →';
    const runnerName = document.createElement('code'); runnerName.textContent = call.runner_request?.name || 'unknown';
    aliasMap.append(modelName, arrow, runnerName);
    modelStage.append(aliasMap, codeViewer('Model tool arguments', call.model_emitted?.arguments || {}));

    const requestStage = document.createElement('section');
    requestStage.className = 'flow-stage request-stage';
    requestStage.innerHTML = '<div class="flow-label"><i></i>2 · Runner received</div>';
    requestStage.append(codeViewer('Canonical MCP request', call.runner_request || {}));

    const responseStage = document.createElement('section');
    responseStage.className = 'flow-stage response-stage';
    responseStage.innerHTML = '<div class="flow-label"><i></i>3 · Model got back</div>';
    responseStage.append(codeViewer('Runner response', call.runner_response));
    flow.append(modelStage, requestStage, responseStage);
    card.append(header, flow);
    group.body.append(card);
  });
  return group.details;
}

function renderTrace(trace) {
  playbackId += 1;
  activeTraceId = trace.trace_id;
  traceEmpty.classList.add('hidden');
  traceLoading.classList.add('hidden');
  traceLive.classList.add('hidden');
  traceContent.classList.remove('hidden');
  traceSelector.value = trace.trace_id;
  document.querySelector('#trace-notice').textContent = trace.notice;
  document.querySelector('#mobile-call-count').textContent = trace.summary?.runner_calls || 0;
  const usage = trace.usage || {};
  const stats = [[trace.summary?.model_turns ?? 0,'Model turns'],[trace.summary?.runner_calls ?? 0,'Runner calls'],[usage.total_tokens ?? '—','Total tokens'],[formatDuration(trace.duration_ms),'Duration']];
  const summary = document.querySelector('#trace-summary');
  summary.replaceChildren(...stats.map(([value, label]) => {
    const node = document.createElement('div'); node.className = 'stat';
    const strong = document.createElement('strong'); strong.textContent = value;
    const span = document.createElement('span'); span.textContent = label;
    node.append(strong, span); return node;
  }));
  traceSections.replaceChildren(renderRunnerCalls(trace), renderModelTurns(trace), renderCatalogs(trace));
}

function addTrace(trace, showInspector = true) {
  traceHistory.unshift(trace);
  traceHistory = traceHistory.slice(0, 10);
  traceSelector.replaceChildren(...traceHistory.map((item, index) => {
    const option = document.createElement('option');
    option.value = item.trace_id;
    option.textContent = `${index === 0 ? 'Latest · ' : ''}${shorten(item.user_message)}`;
    return option;
  }));
  activeTraceId = trace.trace_id;
  traceSelector.value = trace.trace_id;
  document.querySelector('#mobile-call-count').textContent = trace.summary?.runner_calls || 0;
  if (showInspector) renderTrace(trace);
}

function selectTrace(traceId, openMobile = false) {
  const trace = traceHistory.find((item) => item.trace_id === traceId);
  if (!trace) return;
  renderTrace(trace);
  if (openMobile) openTracePanel();
}

function setTraceLoading(message) {
  traceEmpty.classList.add('hidden');
  traceContent.classList.add('hidden');
  traceLoading.classList.remove('hidden');
  document.querySelector('#trace-loading-label').textContent = shorten(message, 80);
}

function setLiveLane(stage, complete = false) {
  liveLane.dataset.stage = stage;
  const order = ['model', 'runner', 'response'];
  const activeIndex = order.indexOf(stage);
  liveLane.querySelectorAll('.live-stage').forEach((node) => {
    const index = order.indexOf(node.dataset.liveStage);
    node.classList.toggle('active', !complete && index === activeIndex);
    node.classList.toggle('done', complete || (activeIndex >= 0 && index < activeIndex));
  });
}

function startLiveTrace(message, mode = 'live') {
  playbackId += 1;
  traceEmpty.classList.add('hidden');
  traceLoading.classList.add('hidden');
  traceContent.classList.add('hidden');
  traceLive.classList.remove('hidden');
  traceLive.classList.toggle('is-replay', mode === 'replay');
  traceLive.classList.toggle('is-inspect', mode === 'inspect');
  liveMode.className = `live-mode ${mode}`;
  liveMode.textContent = mode === 'replay' ? 'REPLAY' : mode === 'inspect' ? 'INSPECT' : 'LIVE';
  liveTitle.textContent = mode === 'replay' ? 'Replaying the request path' : mode === 'inspect' ? 'Inspecting the event sequence' : 'Opening the model boundary';
  liveSubtitle.textContent = mode === 'replay'
    ? `Playing “${shorten(message, 70)}” from recorded event timing.`
    : mode === 'inspect'
      ? 'Use Previous and Next to walk through every captured payload.'
      : `Streaming “${shorten(message, 70)}” as it happens.`;
  liveDetails.classList.add('hidden');
  sequenceNav.classList.add('hidden');
  selectedLiveIndex = -1;
  liveRenderedEvents = [];
  autoFollowLiveEvents = mode !== 'inspect';
  liveEvents.replaceChildren();
  const waiting = document.createElement('div');
  waiting.className = 'live-waiting';
  waiting.innerHTML = '<span></span><div><strong>Waiting for the first event</strong><small>The authenticated session is being prepared…</small></div>';
  liveEvents.append(waiting);
  setLiveLane('system');
}

function updateSequenceControls() {
  const count = liveRenderedEvents.length;
  sequenceNav.classList.toggle('hidden', count === 0);
  sequencePosition.textContent = count ? `${selectedLiveIndex + 1} / ${count}` : '0 / 0';
  sequencePrev.disabled = selectedLiveIndex <= 0;
  sequenceNext.disabled = selectedLiveIndex < 0 || selectedLiveIndex >= count - 1;
}

function selectLiveEvent(index, scroll = true) {
  if (!liveRenderedEvents.length) return;
  selectedLiveIndex = Math.max(0, Math.min(index, liveRenderedEvents.length - 1));
  const event = liveRenderedEvents[selectedLiveIndex];
  const cards = [...liveEvents.querySelectorAll('.live-event-card')];
  cards.forEach((card, cardIndex) => card.classList.toggle('selected', cardIndex === selectedLiveIndex));
  liveTitle.textContent = event.title;
  liveSubtitle.textContent = `${event.kind} · +${formatDuration(event.offset_ms)}`;
  setLiveLane(event.stage);
  updateSequenceControls();
  if (scroll) cards[selectedLiveIndex]?.scrollIntoView({behavior: 'smooth', block: 'center'});
}

function moveLiveSelection(direction) {
  if (!liveRenderedEvents.length) return;
  if (traceLive.classList.contains('is-replay') && !liveMode.classList.contains('complete')) {
    playbackId += 1;
    liveMode.className = 'live-mode paused';
    liveMode.textContent = 'PAUSED';
  }
  autoFollowLiveEvents = false;
  selectLiveEvent(selectedLiveIndex + direction);
}

function livePayloadLabel(event) {
  const labels = {
    'trace.started': 'Trace context',
    'tools.catalog': 'Tools visible to model',
    'model.started': 'Model input',
    'model.completed': 'Raw model output',
    'runner.request': 'Canonical Runner request',
    'runner.response': 'Scoped Runner response',
    'runner.error': 'Runner rejection',
    'trace.completed': 'Trace summary',
  };
  return labels[event.kind] || 'Event payload';
}

function appendLiveEvent(event) {
  liveEvents.querySelector('.live-waiting')?.remove();
  setLiveLane(event.stage);
  liveTitle.textContent = event.title;
  liveSubtitle.textContent = `${event.kind} · +${formatDuration(event.offset_ms)}`;

  const card = document.createElement('article');
  card.className = `live-event-card stage-${event.stage}`;
  const header = document.createElement('div');
  header.className = 'live-event-header';
  const sequence = document.createElement('span');
  sequence.className = 'live-event-sequence';
  sequence.textContent = String(event.sequence).padStart(2, '0');
  const heading = document.createElement('div');
  const title = document.createElement('strong');
  title.textContent = event.title;
  const kind = document.createElement('small');
  kind.textContent = event.kind;
  heading.append(title, kind);
  const timing = document.createElement('time');
  timing.textContent = `+${formatDuration(event.offset_ms)}`;
  header.append(sequence, heading, timing);
  card.append(header, codeViewer(livePayloadLabel(event), event.payload, 'json', {previewLimit: 10000}));
  card.addEventListener('click', (clickEvent) => {
    if (clickEvent.target.closest('button')) return;
    autoFollowLiveEvents = false;
    selectLiveEvent(liveRenderedEvents.indexOf(event));
  });
  liveEvents.append(card);
  liveRenderedEvents.push(event);
  requestAnimationFrame(() => card.classList.add('arrived'));
  if (autoFollowLiveEvents) selectLiveEvent(liveRenderedEvents.length - 1);
  else if (selectedLiveIndex < 0) selectLiveEvent(0, false);
  else updateSequenceControls();
}

function finishLiveTrace(trace) {
  setLiveLane('response', true);
  liveMode.classList.remove('replay');
  liveMode.classList.add('complete');
  liveMode.textContent = traceLive.classList.contains('is-replay') ? 'REPLAYED' : 'COMPLETE';
  liveTitle.textContent = traceLive.classList.contains('is-replay') ? 'Replay complete' : 'Verified answer ready';
  liveSubtitle.textContent = `${trace.summary?.model_turns || 0} model turns · ${trace.summary?.runner_calls || 0} Runner calls · ${formatDuration(trace.duration_ms)}`;
  liveDetails.classList.remove('hidden');
  updateSequenceControls();
}

function failLiveTrace(message) {
  liveMode.className = 'live-mode error';
  liveMode.textContent = 'ERROR';
  liveTitle.textContent = 'The live request stopped';
  liveSubtitle.textContent = message;
}

async function readNdjson(response, onItem) {
  if (!response.body) throw new Error('This browser did not provide a streaming response body.');
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  while (true) {
    const {value, done} = await reader.read();
    buffer += decoder.decode(value || new Uint8Array(), {stream: !done});
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';
    for (const line of lines) {
      if (line.trim()) onItem(JSON.parse(line));
    }
    if (done) break;
  }
  if (buffer.trim()) onItem(JSON.parse(buffer));
}

function wait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function replayTrace(trace) {
  const events = trace?.events || [];
  if (!events.length) {
    showToast('This trace has no replay events');
    return;
  }
  startLiveTrace(trace.user_message, 'replay');
  liveDetails.classList.remove('hidden');
  const thisPlayback = playbackId;
  const speed = Number(document.querySelector('#replay-speed').value) || 0.5;
  liveMode.textContent = `REPLAY ${speed}×`;
  let previousOffset = events[0].offset_ms || 0;
  for (let index = 0; index < events.length; index += 1) {
    if (index > 0) {
      const eventOffset = events[index].offset_ms || previousOffset;
      const recordedGap = Math.max(250, Math.min(1800, eventOffset - previousOffset));
      await wait(Math.max(350, Math.min(2800, recordedGap / speed)));
      previousOffset = eventOffset;
    }
    if (thisPlayback !== playbackId) return;
    appendLiveEvent(events[index]);
  }
  if (thisPlayback === playbackId) finishLiveTrace(trace);
}

function inspectTraceSequence(trace) {
  const events = trace?.events || [];
  if (!events.length) {
    showToast('This trace has no sequence events');
    return;
  }
  startLiveTrace(trace.user_message, 'inspect');
  events.forEach(appendLiveEvent);
  liveDetails.classList.remove('hidden');
  selectLiveEvent(0);
}

function openTracePanel() { experience.classList.add('trace-open'); document.querySelector('#trace-mobile-toggle').setAttribute('aria-expanded','true'); }
function closeTracePanel() { experience.classList.remove('trace-open'); document.querySelector('#trace-mobile-toggle').setAttribute('aria-expanded','false'); }

async function showChat(login) {
  loginForm.classList.add('hidden');
  experience.classList.remove('hidden');
  shell.classList.add('session-open');
  document.querySelector('#identity').textContent = `${login.display_name} · ${login.account.account_name} · ${login.account.membership_role}`;
  setTimeout(() => messageInput.focus(), 100);
}

document.querySelectorAll('.demo-login').forEach((button) => button.addEventListener('click', () => {
  document.querySelector('#email').value = button.dataset.email;
  document.querySelector('#password').value = 'demo123!';
  document.querySelector('#account-number').value = button.dataset.account;
  document.querySelector('#email').focus();
}));

loginForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const error = document.querySelector('#login-error');
  const submit = loginForm.querySelector('button[type="submit"]');
  error.textContent = ''; submit.disabled = true;
  const accountNumber = document.querySelector('#account-number').value.trim();
  try {
    const response = await fetch('/api/login', {method:'POST',credentials:'same-origin',headers:{'content-type':'application/json'},body:JSON.stringify({email:document.querySelector('#email').value,password:document.querySelector('#password').value,account_number:accountNumber || null})});
    const body = await response.json();
    if (response.status === 409 && body.detail?.accounts) {
      const choices = document.querySelector('#account-choices');
      choices.replaceChildren(...body.detail.accounts.map((account) => { const option=document.createElement('option'); option.value=account.account_number; option.label=account.account_name; return option; }));
      error.textContent = `Choose an account number: ${body.detail.accounts.map((account) => account.account_number).join(', ')}`; return;
    }
    if (!response.ok) { error.textContent = typeof body.detail === 'string' ? body.detail : 'Sign-in failed'; return; }
    showChat(body);
  } catch { error.textContent = 'Could not reach the customer portal.'; }
  finally { submit.disabled = false; }
});

chatForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const message = messageInput.value.trim();
  if (!message || sendButton.disabled) return;
  messageInput.value = ''; messageInput.style.height = '';
  document.querySelector('#suggestions')?.remove();
  addMessage('user', message);
  const pending = addMessage('assistant', '', {pending:true});
  sendButton.disabled = true; startLiveTrace(message);
  const requestController = new AbortController();
  const requestTimeout = setTimeout(() => requestController.abort(), 120000);
  try {
    const response = await fetch('/api/chat/stream', {method:'POST',credentials:'same-origin',headers:{'content-type':'application/json','accept':'application/x-ndjson'},body:JSON.stringify({message,chat_session_id:chatSessionId}),signal:requestController.signal});
    if (!response.ok) {
      const body = await response.json();
      throw new Error(typeof body.detail === 'string' ? body.detail : 'I could not complete that request.');
    }
    let body = null;
    let streamError = null;
    const streamedEvents = [];
    await readNdjson(response, (item) => {
      if (item.type === 'session') {
        chatSessionId = item.chat_session_id;
        sessionStorage.setItem('chatSessionId', chatSessionId);
      } else if (item.type === 'trace_event') {
        streamedEvents.push(item.event);
        appendLiveEvent(item.event);
      } else if (item.type === 'complete') {
        body = item.data;
      } else if (item.type === 'error') {
        streamError = item.message;
      }
    });
    if (streamError) throw new Error(streamError);
    if (!body) throw new Error('The live response ended before the final answer arrived.');
    pending.remove();
    chatSessionId = body.chat_session_id;
    sessionStorage.setItem('chatSessionId',chatSessionId);
    body.runner_trace.events = streamedEvents;
    addTrace(body.runner_trace, false);
    finishLiveTrace(body.runner_trace);
    const assistantMessage = addMessage('assistant',body.answer,{trace:body.runner_trace});
    trackProposals(assistantMessage, body.answer);
  } catch (error) { pending.remove(); const message = error.name === 'AbortError' ? 'This request took too long and was stopped. Please try a narrower question.' : error.message || 'The service is temporarily unreachable. Please try again.'; addMessage('assistant',message); failLiveTrace(message); }
  finally { clearTimeout(requestTimeout); sendButton.disabled = false; messageInput.focus(); }
});

messageInput.addEventListener('input', () => { messageInput.style.height='auto'; messageInput.style.height=`${Math.min(messageInput.scrollHeight,145)}px`; });
messageInput.addEventListener('keydown', (event) => { if (event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); chatForm.requestSubmit(); } });
document.querySelectorAll('#suggestions button').forEach((button) => button.addEventListener('click', () => { messageInput.value=button.textContent; chatForm.requestSubmit(); }));
traceSelector.addEventListener('change', () => selectTrace(traceSelector.value));
document.querySelector('#replay-trace').addEventListener('click', () => replayTrace(traceHistory.find((item) => item.trace_id === activeTraceId)));
document.querySelector('#inspect-sequence').addEventListener('click', () => inspectTraceSequence(traceHistory.find((item) => item.trace_id === activeTraceId)));
liveDetails.addEventListener('click', () => selectTrace(activeTraceId));
sequencePrev.addEventListener('click', () => moveLiveSelection(-1));
sequenceNext.addEventListener('click', () => moveLiveSelection(1));
document.querySelector('#copy-trace').addEventListener('click', async () => { const trace=traceHistory.find((item)=>item.trace_id===activeTraceId); if (!trace) return; await navigator.clipboard.writeText(JSON.stringify(trace,null,2)); showToast('Complete trace copied'); });
document.querySelector('#trace-mobile-toggle').addEventListener('click',openTracePanel);
document.querySelector('#trace-close').addEventListener('click',closeTracePanel);
document.querySelector('#trace-scrim').addEventListener('click',closeTracePanel);
document.querySelector('#logout').addEventListener('click',async()=>{await fetch('/api/logout',{method:'POST',credentials:'same-origin'});sessionStorage.clear();location.reload();});

(async function restoreAuthenticatedSession(){const response=await fetch('/api/me',{credentials:'same-origin'});if(!response.ok)return;const me=await response.json();showChat({display_name:me.display_name,account:{account_name:me.account_name,membership_role:me.membership_role}});})();
