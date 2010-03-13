# $Id$
Summary: Automate backup of mysql databases.
Name: mysqlbackup
Version: 2.0
Release: 1.%(date +%%Y%%m%%d).ucd%{?dist}
License: GPL+
Group: Applications/System
URL: https://cvs.lib.ucdavis.edu/viewvc/%{name}
Vendor: UCD Library
Group: System Environment/Shells
Source: %{name}-%{version}.tgz
Provides: %{name}
Buildroot: %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
BuildArch: noarch

%description
Tool to backup MySQL databases and manage binary transaction logs.

%prep
%setup -q -n %{name}

%install
%{__rm}      -fr %{buildroot}
%{__install} -d %{buildroot}%{_bindir}
%{__install} -m 755 %{name}.pl %{buildroot}%{_bindir}/
%{__install} -d %{buildroot}%{_sysconfdir}/cron.daily
%{__install} -d %{buildroot}%{_localstatedir}/backup/mysql
%{__install} -m 755 %{name}.cron %{buildroot}%{_sysconfdir}/cron.daily/%{name}

%clean
%{__rm} -fr %{buildroot}

%files
%defattr(-,root,root)
%attr(644,root,root) %doc README
%{_bindir}/%{name}.pl
%config(noreplace) %{_sysconfdir}/cron.daily/%{name}
%dir %{_localstatedir}/backup/mysql

%changelog
* Thu Mar 12 2010 Dale Bewley <dlbewley@lib.ucdavis.edu>
- Make crontab a config file allowing for local customization

* Wed Oct 07 2009 Dale Bewley <dlbewley@lib.ucdavis.edu>
- Update spec buildroot and release.

* Wed Jul 01 2009 Dale Bewley <dlbewley@lib.ucdavis.edu>
- closer to useful

* Mon Oct 06 2008 Dale Bewley <dlbewley@lib.ucdavis.edu>
- spec skeleton
