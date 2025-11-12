# Multilocal-craft
Un servidor de minecraft que permite la disponibilidad de mundo con despliegues individuales por parte de cada usuario compartiendo datos, asociados por zerotier para permitir solo un depsliegue a la vez y que siempre que alguien quiera usar el mundo, pueda desplegarlo o unirse, asegurando versiones de datos actualizadas del mundo.


Para iniciar el mundo está iniciar.bat que tiene 3 argumentos "docker", "local", "mobile"
"Mobile lanza sin fijar la IP de zero tier y sin docker"
"Local lanza con comandos locales, sin docker"
"Docker despliega el contenedor a partir del compose"