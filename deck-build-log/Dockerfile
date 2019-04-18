FROM registry.fedoraproject.org/fedora

RUN dnf update -y && \
  dnf -y install python2-matplotlib jq findutils && \
  dnf clean all

# Copy in the local directory
COPY . /dashboard

RUN find /dashboard -executable -type f >> /dashboard/command-list.txt

WORKDIR /dashboard

CMD /dashboard/init.sh
