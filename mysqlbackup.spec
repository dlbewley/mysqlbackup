Summary: Automatically backup mysql databases
Name: mysqlbackup
Version: 2.0
Release: 2.%(date +%%Y%%m%%d).bis%{?dist}
License: GPL+
Group: Applications/System
URL: http://www.github.com/dlbewley/%{name}
Group: System Environment/Shells
Source: %{name}-%{version}.tgz
Provides: %{name}
Buildroot: %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
BuildArch: noarch

%description
Tool to backup MySQL databases and rotate binary transaction logs.

%prep
%setup -q -n %{name}

%install
%{__rm}      -fr %{buildroot}
%{__install} -d %{buildroot}%{_bindir}
%{__install} -m 755 %{name}.pl %{buildroot}%{_bindir}/%{name}
%{__install} -d %{buildroot}%{_sysconfdir}/cron.daily
%{__install} -d %{buildroot}%{_sysconfdir}/%{name}
%{__install} -d %{buildroot}%{_localstatedir}/backup/mysql
%{__install} -m 755 %{name}.cron %{buildroot}%{_sysconfdir}/cron.daily/%{name}
%{__install} -m 755 %{name}.cfg %{buildroot}%{_sysconfdir}/%{name}/
%{__install} -m 755 my.cnf %{buildroot}%{_sysconfdir}/%{name}/

%clean
%{__rm} -fr %{buildroot}

%files
%defattr(-,root,root)
%attr(644,root,root) %doc README
%{_bindir}/%{name}
%attr(640,root,root) %config(noreplace) %{_sysconfdir}/%{name}/%{name}.cfg
%attr(640,root,root) %config(noreplace) %{_sysconfdir}/%{name}/my.cnf
%config(noreplace) %{_sysconfdir}/cron.daily/%{name}
%dir %{_localstatedir}/backup/mysql
%dir %{_sysconfdir}/%{name}

%changelog
* Tue Jun 28 2011 Dale Bewley <dale@bewley.net>
- Add config files.
- Rename mysqlbackup.pl to mysqlbackup.

* Thu Mar 12 2010 Dale Bewley <dale@bewley.net>
- Make crontab a config file allowing for local customization

* Wed Oct 07 2009 Dale Bewley <dale@bewley.net>
- Update spec buildroot and release.

* Wed Jul 01 2009 Dale Bewley <dale@bewley.net>
- closer to useful

* Mon Oct 06 2008 Dale Bewley <dale@bewley.net>
- spec skeleton
