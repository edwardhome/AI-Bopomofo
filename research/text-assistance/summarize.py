"""Summarize recorded synthetic inference; never turn template scores into UI claims."""
import collections
import json
import math
import sys
from pathlib import Path

def percentile(values, p):
    return sorted(values)[max(0, math.ceil(len(values)*p)-1)] if values else None

def summarize(report):
    rows=report['rows']
    categories={}
    for category in sorted({r['category'] for r in rows}):
        group=[r for r in rows if r['category']==category]
        categories[category]={
            'count':len(group),
            'first_suggestion_or_original_matches_reference':sum((r['suggestions'] or [r['source']])[0] in r['expected'] for r in group),
            'reference_in_suggestions':sum(any(v in r['expected'] for v in r['suggestions']) for r in group),
            'system_first_or_original_matches_reference':sum((r['baseline'] or [r['source']])[0] in r['expected'] for r in group),
            'cases_with_suggestions':sum(bool(r['suggestions']) for r in group),
        }
    model=[r['milliseconds'] for r in rows]
    total=[r['totalRequestMilliseconds'] for r in rows if 'totalRequestMilliseconds' in r]
    return dict(completed=report['completed'], categories=categories,
                status=dict(collections.Counter(r['status'] for r in rows)),
                provider_ms=dict(p50=percentile(model,.5),p95=percentile(model,.95),p99=percentile(model,.99)),
                request_with_system_spelling_ms=dict(p50=percentile(total,.5),p95=percentile(total,.95),p99=percentile(total,.99)),
                caveats='Individually authored synthetic examples, not independently reviewed. UI keeps original first. No GUI/key-event latency measurement. Warm model and background build load not isolated.')
if __name__=='__main__':
    path=Path(sys.argv[1])
    print(json.dumps(summarize(json.loads(path.read_text())),ensure_ascii=False,indent=2))
