# Makefile for source rpm: kexec-tools
# $Id$
NAME := kexec-tools
SPECFILE = $(firstword $(wildcard *.spec))

SUBDIRS = kcp

include ../common/Makefile.common
