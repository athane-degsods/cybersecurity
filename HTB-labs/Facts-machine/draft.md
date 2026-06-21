# Machine:
- Name: Facts
- Diff: Easy
- OS: Linux
- IP: 10.129.31.174
- Start time: 10:30, June 18
- Scope: User and Root priv

---

# Workflow

# 1. Host discovery:

eren@magi:~/cybersecurity/HTB-labs/Facts-machine % ping -c 2 10.129.31.174
PING 10.129.31.174 (10.129.31.174) 56(84) bytes of data.
64 bytes from 10.129.31.174: icmp_seq=1 ttl=63 time=167 ms
64 bytes from 10.129.31.174: icmp_seq=2 ttl=63 time=89.0 ms

--- 10.129.31.174 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1001ms
rtt min/avg/max/mdev = 89.048/127.883/166.719/38.835 ms

== CONFIRM: host is on and vpn is connected

# 2. Service enum

## a. nmap full scan
eren@magi:~/cybersecurity/HTB-labs/Facts-machine % sudo nmap -p- -T4 --min-rate 1000 --open 10.129.31.174 -oN scan/Facts-tcp-full.txt
Starting Nmap 7.99 ( https://nmap.org ) at 2026-06-18 22:38 -0700
Nmap scan report for 10.129.31.174
Host is up (0.18s latency).
Not shown: 65532 closed tcp ports (reset)
PORT      STATE SERVICE
22/tcp    open  ssh
80/tcp    open  http
54321/tcp open  unknown

## b. deeper scan on open ports

eren@magi:~/cybersecurity/HTB-labs/Facts-machine % sudo nmap -p 22,80,54321 -Pn -sV -sC 10.129.31.174 -oN scan/Facts-deep-port.txt 
@file: scan/Facts-deep-port.txt

## c. Analysis

1. Port 22:tcp (SSH)
version: OpenSSH 9.9p1 Ubuntu 3ubuntu3.2 (Ubuntu Linux; protocol 2.0)
ssh-hostkeys: ECDSA, ED25519

2. Port 80:tcp (HTTP)
version: nginx/1.26.3 (Ubuntu)
http-title: Did not follow redirect to http://facts.htb/

3. Port 54321:tcp (HTTP)
header: MinIO
http-title: Did not follow redirect to http://10.129.31.174:9001 

==> Deep enum order Web (80, 54321) -> SSH (22)

## d. Web enum (80)

1. curl the web base
@file: port-80/base.txt 
--> 302, location: http://facts.htb

2. add web page to /etc/hosts

3. Try curl again
worked. @file: port-80/facts.txt

4. Generic web paths

/admin -> /admin/login
+ login page
+ create account page
+ forgot account page

5. Version vulnerability enum

- searchsploit
nothing

- msfconsole
nothing

6. Vhost enum

- gobuster
eren@magi:~/cybersecurity/HTB-labs/Facts-machine/port-80/vhost-dis % gobuster vhost --wordlist /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt --append-domain -o vhost-gobuster.txt --url http://facts.htb

7. Dir enum

-gobuster: 
eren@magi:~/cybersecurity/HTB-labs/Facts-machine % gobuster dir --wordlist /usr/share/seclists/Discovery/Web-Content/DirBuster-2007_directory-list-2.3-medium.txt --url http://facts.htb -o port-80/dir-dis/dir-gobuster.txt
@file: dir-dis/dir-gobuster.txt

==> Found people on the blog page: bob, carol, dave, 

8. Try to create account 

- use `admin` username for creating account: rejected
=> admin is a valid credential

- register `admin1:admin`credential: success
=> There are uploadable fields: Avatar photos
=> /admin/profile is prohibited

--- 
Potential vul:
1. File uploading (via avatar image)
2. weak credential (via `admin` username)

9. Camaleon vuln (version 2.9.0)

auth_token: x2ZxAr7CHaKY_v50EJTtXQ&Mozilla/5.0+(X11;+Linux+x86_64;+rv:148.0)+Gecko/20100101+Firefox/148.0&10.10.17.119
