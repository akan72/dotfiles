alias config='/usr/bin/git --git-dir=/Users/lexokan/.cfg/ --work-tree=/Users/lexokan'

export HADOOP_HOME=~/spark/hadoop-2.7.7
export PATH=$PATH:~/spark/hadoop-2.7.7/bin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HADOOP_HOME/lib/native
export HADOOP_OPTS="$HADOOP_OPTS -Djava.library.path=$HADOOP_HOME/lib/native"

export SPARK_HOME=~/spark/spark-2.4.5-bin-hadoop2.7
export PATH=$PATH:~/spark/spark-2.4.5-bin-hadoop2.7/bin

export PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.7-src.zip:$PYTHONPATH
export PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/:$PYTHONPATH
export PATH=$PATH:${SPARK_HOME}/python

export PYSPARK_DRIVER_PYTHON=jupyter
export PYSPARK_DRIVER_PYTHON_OPTS='notebook'

