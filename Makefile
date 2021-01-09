all:	rpi-carbidemotion.zip



rpi-carbidemotion.zip: build.sh launch-cm.c
	rm -f rpi-carbidemotion.img
	bash build.sh
	
	
	
clean:
	rm -f *~ DEADJOE rpi-carbidemotion.img