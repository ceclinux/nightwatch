# Draft messages: survey photos (for the owner to send)

**Status, 7 November 2026:** kept as a record. The CDS message (section 1) was sent and CDS replied on 3 November (see the licence note in
`docs/plans/2026-11-03-release-1.0.1-and-1.7.2.md`); this repository does not record whether the Stellarium message (section 2) was sent. The
picture set no longer depends on either: it is built from the IRSA and CASDA mirrors of the same survey.

As written on 1 November 2026 (not to be committed with a feature PR; it has its own docs-only PR): check both addresses on the recipients' own
websites before sending: I could not read the CDS site (it is down) and found no contact page for Stellarium's survey server, so neither address is verified.

Facts behind the drafts (checked 1 November 2026): CDS's hips2fits, SIMBAD and cds.unistra.fr have not answered from this Mac since about
26 October, and the fetch tool gets "connection refused" too, so it is not local. The alaskybis mirror and the older u-strasbg.fr names also fail.
STScI's DSS terms: non-profit research and teaching use with acknowledgement; commercial use needs permission; POSS-II and UKSTU plates
have other rights holders. Nightwatch is free, MIT-licensed, with no ads and no in-app purchases.

---

## 1. To CDS (Strasbourg astronomical Data Center)

**To:** the CDS contact address on cds.unistra.fr (usually `cds-question@unistra.fr`; please confirm)
**Subject:** hips2fits unreachable since about 26 October, and a question about caching cutouts

Dear CDS team,

I write Nightwatch, a free, open-source (MIT) astrophotography planner for Mac, iPhone and iPad (https://github.com/rsutcliffe/nightwatch;
https://apps.apple.com/gb/app/nightwatch-clear-sky-alerts/id6816390602). It shows a small DSS2 colour picture of each target from your
hips2fits service (`CDS/P/DSS2/color`, 480 px wide, one request per target the first time it is shown, kept on the user's device).

Two things, please.

1. **Status.** Since about 26 October 2026, `alasky.cds.unistra.fr`, `alaskybis.cds.unistra.fr`, `cds.unistra.fr` and SIMBAD time out from the
   UK and from a second network. I saw that the University of Strasbourg took several websites offline on 21 October after a security vulnerability; if that is the cause, I would be glad to know. Is this a known problem, and is there an expected time for service to return? A pointer to a status page would also help.

2. **A small fixed set of pictures.** Today every user's first view of a target is a live request. To make this lighter on your service
   and to keep the app working through an outage, I would like to prepare one 480 × 274 JPEG or WebP of DSS2 colour for each of about 2,000
   catalogue targets (roughly 30 to 55 MB in total, fetched once, politely, one request at a time) and ship or host that set with the app, with
   the acknowledgement your rules ask for. May I do this, and is there wording you would like in the credit? The app already credits CDS,
   the Digitized Sky Survey and its plate owners.

Thank you for a service the app depends on. I am glad to adjust to whatever you prefer.

Richard Sutcliffe
https://github.com/rsutcliffe/nightwatch

---

## 2. To Stellarium (survey data server)

**To:** the Stellarium team: use the contact route on stellarium.org or open a discussion in the Stellarium GitHub repository (no address for
`data.stellarium.org` was found; please check which they prefer)
**Subject:** Permission to use the DSS colour survey on data.stellarium.org for small cutouts

Hello,

I write Nightwatch, a free, open-source (MIT) astrophotography planner for Mac, iPhone and iPad (https://github.com/rsutcliffe/nightwatch).
It shows a small picture of each target, normally from CDS's hips2fits service, which has been unreachable since about 26 October 2026.

Your server lists a Digitized Sky Survey colour HiPS at `https://data.stellarium.org/surveys/dss`. Would you allow me to use it as a
back-up source? What I have in mind is small and slow:

- about 2,000 cutouts, one per catalogue target, built once by fetching the few 512 px tiles each needs, one request at a time with pauses;
- the result is roughly 30 to 55 MB in total, shipped or hosted with the app, so users do not request tiles themselves;
- the app is free, with no ads and no in-app purchases, and would credit the Digitized Sky Survey, the plate owners, CDS HiPS and Stellarium.

Please tell me whether that is acceptable, what credit you would like, and whether a different arrangement suits you better (for example, I
use the CDS service when it returns, and your tiles only for this one-off build). If the survey's terms come from STScI or the plate owners
rather than from you, a pointer to the right place would be enough.

Thank you,
Richard Sutcliffe
https://github.com/rsutcliffe/nightwatch
