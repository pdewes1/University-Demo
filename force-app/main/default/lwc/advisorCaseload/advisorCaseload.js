import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getCaseload from '@salesforce/apex/AdvisorCaseloadController.getCaseload';

const PAGE = 8;
const FILTERS = [
    { value: 'attention', label: 'Needs attention' },
    { value: 'watch', label: 'Watch' },
    { value: 'all', label: 'All students' },
    { value: 'leave', label: 'On leave' }
];

export default class AdvisorCaseload extends NavigationMixin(LightningElement) {
    caseload;
    error;
    filter = 'attention';
    showAll = false;
    refreshing = false;
    wiredResult;

    @wire(getCaseload)
    wired(result) {
        this.wiredResult = result;
        const { data, error } = result;
        this.caseload = data;
        this.error = error ? (error.body && error.body.message) || 'Could not load your caseload.' : undefined;
        if (data && data.needsAttention === 0 && this.filter === 'attention') this.filter = 'all';
    }

    get loading() { return !this.caseload && !this.error; }
    get c() { return this.caseload || {}; }
    get notice() { return this.c.message; }
    get hasStudents() { return (this.c.totalStudents || 0) > 0; }

    // ---- KPI tiles -------------------------------------------------------------
    get tiles() {
        const c = this.c;
        const avg = c.averageEngagement === undefined || c.averageEngagement === null ? '–' : c.averageEngagement;
        return [
            { key: 'students', label: 'My students', value: c.totalStudents || 0, detail: `Avg engagement ${avg}`, icon: 'utility:people', cls: 'tile tile_brand' },
            { key: 'attention', label: 'Need attention', value: c.needsAttention || 0, detail: 'Ranked first below', icon: 'utility:warning', cls: 'tile ' + ((c.needsAttention || 0) > 0 ? 'tile_risk' : 'tile_good') },
            { key: 'overdue', label: 'Overdue follow-ups', value: c.overdueFollowUps || 0, detail: 'Open tasks past due', icon: 'utility:clock', cls: 'tile ' + ((c.overdueFollowUps || 0) > 0 ? 'tile_risk' : 'tile_good') },
            { key: 'contact', label: 'No contact in 30 days', value: c.noRecentContact || 0, detail: 'Including never contacted', icon: 'utility:call', cls: 'tile ' + ((c.noRecentContact || 0) > 0 ? 'tile_watch' : 'tile_good') },
            { key: 'aid', label: 'Aid to follow up', value: c.aidActionNeeded || 0, detail: 'FAFSA, verification or SAP', icon: 'utility:moneybag', cls: 'tile ' + ((c.aidActionNeeded || 0) > 0 ? 'tile_watch' : 'tile_good') }
        ];
    }

    // ---- Filters ---------------------------------------------------------------
    get filters() {
        const counts = this.counts;
        return FILTERS.map((f) => ({
            ...f,
            text: `${f.label} (${counts[f.value]})`,
            cls: 'pill' + (this.filter === f.value ? ' pill_on' : ''),
            pressed: this.filter === f.value ? 'true' : 'false'
        }));
    }
    get counts() {
        const rows = this.c.students || [];
        return {
            attention: rows.filter((r) => r.needsAttention).length,
            watch: rows.filter((r) => r.status === 'Watch').length,
            all: this.c.totalStudents || 0,
            leave: rows.filter((r) => r.onLeave).length
        };
    }
    handleFilter(event) {
        this.filter = event.currentTarget.dataset.value;
        this.showAll = false;
    }

    // ---- Rows --------------------------------------------------------------------
    get filtered() {
        const rows = this.c.students || [];
        switch (this.filter) {
            case 'attention': return rows.filter((r) => r.needsAttention);
            case 'watch': return rows.filter((r) => r.status === 'Watch');
            case 'leave': return rows.filter((r) => r.onLeave);
            default: return rows;
        }
    }
    get rows() {
        const list = this.showAll ? this.filtered : this.filtered.slice(0, PAGE);
        return list.map((r) => this.decorate(r));
    }
    get hasRows() { return this.filtered.length > 0; }
    get moreCount() { return this.filtered.length - PAGE; }
    get showMore() { return !this.showAll && this.filtered.length > PAGE; }
    get moreLabel() { return `Show all ${this.filtered.length}`; }
    get truncatedNote() {
        return this.c.truncated ? `Showing the ${(this.c.students || []).length} students who most need attention out of ${this.c.totalStudents}.` : null;
    }
    handleMore() { this.showAll = true; }

    decorate(r) {
        const band = r.engagementBand;
        const bandKey = band === 'On track' ? 'good' : band === 'Watch' ? 'watch' : band === 'At risk' ? 'risk' : 'none';
        const flags = r.flags || [];
        const shown = flags.slice(0, 3).map((f, i) => ({ key: r.id + '_f' + i, label: f }));
        const statusKey = r.status === 'Needs attention' ? 'risk' : r.status === 'Watch' ? 'watch' : 'good';
        return {
            ...r,
            initials: (r.name || '?').split(' ').map((p) => p.charAt(0)).slice(0, 2).join('').toUpperCase(),
            avatarCls: 'avatar avatar_' + statusKey,
            subline: [r.program, r.studentId].filter(Boolean).join(' · '),
            scoreText: r.engagementScore === undefined || r.engagementScore === null ? '–' : r.engagementScore,
            scoreCls: 'score score_' + bandKey,
            bandText: band || 'No score',
            statusCls: 'status status_' + (r.onLeave ? 'none' : statusKey),
            statusText: r.onLeave ? 'On leave' : r.status,
            attendanceText: r.attendanceRate === undefined || r.attendanceRate === null ? '–' : r.attendanceRate + '%',
            loginText: r.daysSinceLogin === undefined || r.daysSinceLogin === null ? '–'
                : r.daysSinceLogin === 0 ? 'Today' : r.daysSinceLogin + 'd ago',
            contactText: r.daysSinceContact === undefined || r.daysSinceContact === null ? 'Never'
                : r.daysSinceContact === 0 ? 'Today' : r.daysSinceContact + 'd ago',
            aidText: r.aidStatus || '–',
            aidCls: 'metric-value' + (r.aidAction ? ' metric_watch' : ''),
            followText: r.overdueFollowUps > 0 ? `${r.overdueFollowUps} overdue` : `${r.openFollowUps || 0} open`,
            followCls: 'metric-value' + (r.overdueFollowUps > 0 ? ' metric_risk' : ''),
            flags: shown,
            extraFlags: flags.length > 3 ? `+${flags.length - 3} more` : null,
            hasFlags: flags.length > 0
        };
    }

    handleOpen(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, objectApiName: 'Contact', actionName: 'view' }
        });
    }

    async handleRefresh() {
        this.refreshing = true;
        try {
            await refreshApex(this.wiredResult);
        } finally {
            this.refreshing = false;
        }
    }
}
