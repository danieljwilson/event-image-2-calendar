import { ExtractionLog, StoredEventPayload } from './types';

export function buildDashboardHTML(logs: ExtractionLog[], events: StoredEventPayload[], daysFilter: number): string {
  const totalExtractions = logs.length;
  const totalCost = logs.reduce((sum, l) => sum + l.totalCostUsd, 0);
  const successCount = logs.filter((l) => l.success).length;
  const successRate = totalExtractions > 0 ? ((successCount / totalExtractions) * 100).toFixed(1) : '0';
  const avgTime =
    totalExtractions > 0
      ? (logs.reduce((sum, l) => sum + l.processingTimeSec, 0) / totalExtractions).toFixed(1)
      : '0';
  const uniqueDevices = new Set(logs.map((l) => l.deviceId)).size;

  const todayStr = new Date().toISOString().slice(0, 10);
  const todayCount = logs.filter((l) => l.timestamp.startsWith(todayStr)).length;
  const todayCost = logs.filter((l) => l.timestamp.startsWith(todayStr)).reduce((s, l) => s + l.totalCostUsd, 0);

  const eventRows = events
    .sort((a, b) => b.startDate.localeCompare(a.startDate))
    .map((e) => {
      const date = new Date(e.startDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' });
      const statusClass = e.eventStatus === 'added' ? 'ok' : e.eventStatus === 'failed' ? 'err' : '';
      const statusBadge = statusClass
        ? `<span class="badge ${statusClass}">${escapeHtml(e.eventStatus ?? 'unknown')}</span>`
        : escapeHtml(e.eventStatus ?? 'unknown');
      return `<tr>
        <td>${escapeHtml(e.title)}</td>
        <td>${escapeHtml(e.category ?? '-')}</td>
        <td>${escapeHtml(e.city ?? '-')}</td>
        <td>${escapeHtml(e.venue)}</td>
        <td>${escapeHtml(date)}</td>
        <td>${statusBadge}</td>
        <td title="${escapeHtml(e.deviceId)}">${escapeHtml(e.deviceId.slice(0, 8))}</td>
      </tr>`;
    })
    .join('\n');

  const rows = logs
    .sort((a, b) => b.timestamp.localeCompare(a.timestamp))
    .map((l) => {
      const time = new Date(l.timestamp).toLocaleString('en-US', {
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        timeZone: 'UTC',
      });
      const device = l.deviceId.slice(0, 8);
      const status = l.success
        ? '<span class="badge ok">OK</span>'
        : `<span class="badge err" title="${escapeHtml(l.errorDetail ?? '')}">ERR</span>`;
      return `<tr>
        <td>${escapeHtml(time)}</td>
        <td title="${escapeHtml(l.deviceId)}">${escapeHtml(device)}</td>
        <td>${escapeHtml(l.modality ?? '-')}</td>
        <td>${escapeHtml(l.model)}</td>
        <td class="num">${l.inputTokens.toLocaleString()}</td>
        <td class="num">${l.outputTokens.toLocaleString()}</td>
        <td class="num">$${l.inputCostUsd.toFixed(4)}</td>
        <td class="num">$${l.outputCostUsd.toFixed(4)}</td>
        <td class="num">$${l.totalCostUsd.toFixed(4)}</td>
        <td class="num">${l.processingTimeSec.toFixed(1)}s</td>
        <td>${status}</td>
      </tr>`;
    })
    .join('\n');

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Event Snap — Extraction Analytics</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f7; color: #1d1d1f; padding: 24px; }
  h1 { font-size: 24px; font-weight: 600; margin-bottom: 8px; }
  .subtitle { color: #86868b; font-size: 14px; margin-bottom: 24px; }
  .cards { display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 24px; }
  .card { background: #fff; border-radius: 12px; padding: 16px 20px; min-width: 140px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
  .card .label { font-size: 12px; color: #86868b; text-transform: uppercase; letter-spacing: 0.5px; }
  .card .value { font-size: 24px; font-weight: 600; margin-top: 4px; }
  .card .sub { font-size: 12px; color: #86868b; margin-top: 2px; }
  .filters { margin-bottom: 16px; display: flex; gap: 8px; }
  .filters a { padding: 6px 14px; border-radius: 8px; background: #fff; color: #1d1d1f; text-decoration: none; font-size: 13px; border: 1px solid #d2d2d7; }
  .filters a.active { background: #0071e3; color: #fff; border-color: #0071e3; }
  table { width: 100%; border-collapse: collapse; background: #fff; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
  th { text-align: left; padding: 10px 12px; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; color: #86868b; background: #fafafa; border-bottom: 1px solid #e5e5ea; }
  td { padding: 8px 12px; font-size: 13px; border-bottom: 1px solid #f2f2f7; }
  td.num { text-align: right; font-variant-numeric: tabular-nums; }
  tr:last-child td { border-bottom: none; }
  tr:hover { background: #f5f5f7; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: 600; }
  .badge.ok { background: #d4edda; color: #155724; }
  .badge.err { background: #f8d7da; color: #721c24; cursor: help; }
  .empty { padding: 40px; text-align: center; color: #86868b; }
</style>
</head>
<body>
<h1>Event Snap Analytics</h1>
<p class="subtitle">${totalExtractions} extractions from ${uniqueDevices} device${uniqueDevices !== 1 ? 's' : ''} (last ${daysFilter} days, UTC)</p>

<div class="cards">
  <div class="card"><div class="label">Today</div><div class="value">${todayCount}</div><div class="sub">$${todayCost.toFixed(4)}</div></div>
  <div class="card"><div class="label">Total Cost</div><div class="value">$${totalCost.toFixed(4)}</div></div>
  <div class="card"><div class="label">Success Rate</div><div class="value">${successRate}%</div></div>
  <div class="card"><div class="label">Avg Time</div><div class="value">${avgTime}s</div></div>
  <div class="card"><div class="label">Devices</div><div class="value">${uniqueDevices}</div></div>
</div>

<div class="filters">
  ${[1, 7, 30, 90].map((d) => `<a href="?days=${d}&key=KEY_PLACEHOLDER" class="${d === daysFilter ? 'active' : ''}">${d}d</a>`).join('')}
</div>

${
  totalExtractions === 0
    ? '<div class="empty">No extractions in this period.</div>'
    : `<table>
<thead><tr>
  <th>Time</th><th>Device</th><th>Modality</th><th>Model</th>
  <th>In Tokens</th><th>Out Tokens</th><th>In Cost</th><th>Out Cost</th><th>Total Cost</th>
  <th>Time</th><th>Status</th>
</tr></thead>
<tbody>
${rows}
</tbody>
</table>`
}

<h2 style="margin-top:32px; margin-bottom:16px;">Events (${events.length})</h2>
${
  events.length === 0
    ? '<div class="empty">No events stored.</div>'
    : `<table>
<thead><tr>
  <th>Title</th><th>Category</th><th>City</th><th>Venue</th><th>Date</th><th>Status</th><th>Device</th>
</tr></thead>
<tbody>
${eventRows}
</tbody>
</table>`
}
</body>
</html>`;
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
