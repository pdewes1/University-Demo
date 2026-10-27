import { LightningElement, api, wire } from 'lwc';
import getSnapshot from '@salesforce/apex/Student360CardController.getSnapshot';

const RING_RADIUS = 52;
const RING_LENGTH = 2 * Math.PI * RING_RADIUS;

export default class Student360Card extends LightningElement {
    @api recordId;
    snapshot;
    error;

    @wire(getSnapshot, { recordId: '$recordId' })
    wired({ data, error }) {
        this.snapshot = data;
        this.error = error ? (error.body && error.body.message) || 'Could not load Data 360.' : undefined;
    }

    get loading() { return !this.snapshot && !this.error; }
    get s() { return this.snapshot || {}; }
    get hasData() { return this.s.available; }
    get notice() { return this.s.message; }

    // Engagement ring
    get hasScore() { return this.s.engagementScore !== undefined && this.s.engagementScore !== null; }
    get scoreText() { return this.hasScore ? Math.round(this.s.engagementScore) : '–'; }
    get bandText() { return this.s.engagementBand || 'No score yet'; }
    get bandClass() {
        const b = this.s.engagementBand;
        return 'band ' + (b === 'On track' ? 'band_good' : b === 'Watch' ? 'band_watch' : b === 'At risk' ? 'band_risk' : 'band_none');
    }
    get ringClass() { return this.bandClass.replace('band ', 'ring-value ring-'); }
    get ringDash() {
        const pct = this.hasScore ? Math.max(0, Math.min(100, this.s.engagementScore)) : 0;
        return `${(pct / 100) * RING_LENGTH} ${RING_LENGTH}`;
    }

    // Flags
    get flags() { return (this.s.flags || []).map((label, i) => ({ key: 'f' + i, label })); }
    get hasFlags() { return this.flags.length > 0; }

    // Tiles
    get tiles() {
        const s = this.s;
        const pct = (v) => (v === undefined || v === null ? '–' : v + '%');
        const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;
        return [
            {
                key: 'att', icon: 'utility:event', label: 'Attendance', value: pct(s.attendanceRate),
                detail: s.absences ? `${plural(s.absences, 'absence')} · last ${s.lastAbsence}` : `${plural(s.classesRecorded || 0, 'class')} recorded, no absences`,
                tone: this.tone(s.attendanceRate, 90, 80)
            },
            {
                key: 'sub', icon: 'utility:check', label: 'On-time work', value: pct(s.onTimeRate),
                detail: `${s.lateSubmissions || 0} late · ${s.missingSubmissions || 0} missing`,
                tone: this.tone(s.onTimeRate, 90, 75)
            },
            {
                key: 'score', icon: 'utility:education', label: 'Course average', value: pct(s.averageScore),
                detail: `${plural((s.courses || []).length, 'course')} this term`,
                tone: this.tone(s.averageScore, 80, 70)
            },
            {
                key: 'lms', icon: 'utility:desktop', label: 'LMS activity', value: String(s.pageViews || 0),
                detail: `page views · ${s.lmsMinutes || 0} min${s.lastLogin ? ' · last login ' + s.lastLogin : ''}`,
                tone: this.tone(s.pageViews, 10, 5)
            },
            {
                key: 'disc', icon: 'utility:comments', label: 'Discussion', value: String(s.discussionPosts || 0),
                detail: 'posts in the last 30 days',
                tone: (s.discussionPosts || 0) > 0 ? 'good' : 'watch'
            },
            {
                key: 'adv', icon: 'utility:user', label: 'Advising contact',
                value: s.daysSinceContact === undefined || s.daysSinceContact === null ? 'None' : s.daysSinceContact + 'd',
                detail: (s.lastAdvisingContact ? 'last ' + s.lastAdvisingContact : 'no contact recorded') + ` · ${plural(s.overdueFollowUps || 0, 'overdue follow-up')}`,
                tone: s.daysSinceContact === undefined || s.daysSinceContact === null ? 'risk'
                    : s.daysSinceContact > 30 || s.overdueFollowUps > 0 ? 'watch' : 'good'
            }
        ].map((t) => ({ ...t, cls: 'tile tile_' + t.tone }));
    }

    tone(v, good, watch) {
        if (v === undefined || v === null) return 'none';
        return v >= good ? 'good' : v >= watch ? 'watch' : 'risk';
    }

    // Courses
    get courses() {
        return (this.s.courses || []).map((c, i) => ({
            key: 'c' + i, label: c.courseId,
            score: c.currentScore === undefined || c.currentScore === null ? '' : c.currentScore + '%',
            cls: 'course course_' + this.tone(c.currentScore, 80, 70)
        }));
    }
    get hasCourses() { return this.courses.length > 0; }

    // Financial aid (status only)
    get aid() {
        const s = this.s;
        const ok = (v, goodValues) => (v ? (goodValues.includes(v.toLowerCase()) ? 'good' : 'watch') : 'none');
        return [
            { key: 'fafsa', label: 'FAFSA', value: s.fafsaStatus || '–', tone: ok(s.fafsaStatus, ['received']) },
            { key: 'ver', label: 'Verification', value: s.verificationStatus || '–', tone: ok(s.verificationStatus, ['not selected', 'selected - complete']) },
            { key: 'sap', label: 'Academic progress', value: s.sapStatus || '–', tone: ok(s.sapStatus, ['met']) }
        ].map((a) => ({ ...a, cls: 'aid-pill aid_' + a.tone }));
    }
    get aidYear() { return this.s.aidYear ? 'Aid year ' + this.s.aidYear : 'Financial aid'; }
}
