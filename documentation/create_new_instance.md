# Creating a new instance

If you wish to create a new CVEDIA-RT instance that runs on VICON devices based on footage stored on disk, you need to:
1. Ensure your video is converted to a sequence of images
2. Create the instance configuration
3. Send the instance configuration to the device
4. Run the instance on the device
5. Visualize the results on your desktop

## Ensure your video is converted to a sequence of images

Since we can't use a video reader library on the device, we need to convert the video to a sequence of images. This should be done using FFMPEG.

Assuming you have a video named `input.mp4`, run the following command

```
ffmpeg -i input.mp4 -qscale:v 3  -vf "scale=-1:720" output_%04d.jpg
```

This will extract all the frames from the video in the current folder.
Once this is done, move the images to the folder `assets/videos/my_new_video`

## Create the instance configuration

Let's assume you want to test person line crossing on the video extracted above. 

Create a new `.json` file in the root of the package, named `my_person_line_crossing.json`, and paste this into it

```
{
 "Input": {
   "VideoReader": {
    "realtime_directory_playback": true
   },
   "uri": "file:///assets/videos/my_new_video"
 },
  "Tripwires": {
   "tripwires": [
    {
     "class_filter": "person",
     "max_object_size": "small",
     "direction": "Both",
     "name": "1",
     "shape": [
      [
       656.5994262695313,
       432.9230651855469
      ],
      [
       538.55908203125,
       422.76922607421875
      ]
     ],
     "wireid": 1.0
    }
   ],
   "zones": [
   ]
  }
 }
```

This configuration will set up one tripwire to detect small people crossings, and expects small objects (please refer to the capabilities page for more info on the available capabilities and their settings).

You can use CVEDIA-RT on your desktop to facilitate the creation of triggers and zones.

## Send the instance configuration to the device

Assuming the CVEDIA-RT binary is located at `/mnt/mmc/redist` in the device, you can use the following command to put the configuration file in the proper place

```
cat my_person_line_crossing.json | ssh <user>@<ip> "cat > /mnt/mmc/redist/assets/projects/perimeter-security/my_person_line_crossing.json"
```

where `<user>` is the SSH username and `<ip>` is the IP of the device


## Run the instance on the device

Once logged in the device (and assuming the CVEDIA-RT binary is located at `/mnt/mmc/redist`), you can use the following command to start the instance created above

```
cd /mnt/mmc/redist
./runinstance -c assets/projects/perimeter-security/my_person_line_crossing.json -v
```

## Visualize the results on your desktop

Once the instance is running on the device, you can visualize the output on your desktop by running the following command

```
python zmq_receive.py --ip <device_ip>
```