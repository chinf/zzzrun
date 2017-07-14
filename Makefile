PREFIX := /usr/local

all:

install:
	install -d $(DESTDIR)/etc/cron.d
	install -d $(DESTDIR)/etc/cron.daily
	install -d $(DESTDIR)/etc/cron.hourly
	install -d $(DESTDIR)/etc/cron.weekly
	install -d $(DESTDIR)/etc/cron.monthly
	install -m 0644 etc/zzzrun.cron.frequent $(DESTDIR)/etc/cron.d/zzzrun
	install etc/zzzrun.cron.hourly   $(DESTDIR)/etc/cron.hourly/zzzrun
	install etc/zzzrun.cron.daily    $(DESTDIR)/etc/cron.daily/zzzrun
	install etc/zzzrun.cron.weekly   $(DESTDIR)/etc/cron.weekly/zzzrun
	install etc/zzzrun.cron.monthly  $(DESTDIR)/etc/cron.monthly/zzzrun
	install -d $(DESTDIR)$(PREFIX)/share/man/man8
	install -m 0644 src/zzzrun.8 $(DESTDIR)$(PREFIX)/share/man/man8/zzzrun.8
	gzip $(DESTDIR)$(PREFIX)/share/man/man8/zzzrun.8
	install -d $(DESTDIR)$(PREFIX)/bin
	install src/zzzrun.sh $(DESTDIR)$(PREFIX)/bin/zzzrun
