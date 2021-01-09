all:	rpi-carbidemotion.zip



rpi-carbidemotion.zip: build.sh launch-cm.c
	bash build.sh
	
	
	
clean:
	rm -f *~ DEADJOE rpi-carbidemotion.img