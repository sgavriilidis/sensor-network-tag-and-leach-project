#include "SimpleRoutingTree.h"
#include <stdio.h>
#include <stdlib.h>
#include "time.h"

#ifdef PRINTFDBG_MODE
	#include "printf.h"
#endif



module SRTreeC
{
	uses interface Boot;
	uses interface SplitControl as RadioControl;


	uses interface AMSend as RoutingAMSend;
	uses interface AMPacket as RoutingAMPacket;
	uses interface Packet as RoutingPacket;
	
	uses interface AMSend as NotifyAMSend;
	uses interface AMPacket as NotifyAMPacket;
	uses interface Packet as NotifyPacket;


	uses interface Timer<TMilli> as RoutingMsgTimer;
	uses interface Timer<TMilli> as LostTaskTimer;
	
	uses interface Receive as RoutingReceive;
	uses interface Receive as NotifyReceive;

	
	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;
	
	uses interface PacketQueue as NotifySendQueue;
	uses interface PacketQueue as NotifyReceiveQueue;

	uses interface Timer<TMilli> as valueGenerator;   // will generate the rand value
	uses interface Timer<TMilli> as NotifyParentMsgTimer;       // will display average & variance 
	uses interface Timer<TMilli> as leaderGenerator;
}

implementation
{
	bool imLeader=FALSE;
	bool iwasLeader=FALSE;
	


	int nodeChildren=0;
	uint16_t  roundCounter;
	int i;


	message_t radioRoutingSendPkt;
	message_t radioNotifySendPkt;
	
	
	
	bool RoutingSendBusy=FALSE;
	bool NotifySendBusy=FALSE;


	
	bool lostRoutingSendTask=FALSE;
	bool lostNotifySendTask=FALSE;
	bool lostRoutingRecTask=FALSE;
	bool lostNotifyRecTask=FALSE;
	
	uint8_t curdepth;
	uint16_t parentID;
	
	uint16_t sumOld=-1;
	uint16_t squaresOld=-1;
	uint16_t childrenOld=-1;
	uint16_t value;
	int sum;
	uint16_t squares;
	uint16_t children;
	double avg = 0;
	double variance = 0;
	
	task void sendRoutingTask();
	task void sendNotifyTask();
	task void receiveRoutingTask();
	task void receiveNotifyTask();
	task void NotifyParentMsgTask();

	void setNotifySendBusy(bool state);
	void setRoutingSendBusy(bool state);
	void setLostRoutingSendTask(bool state);
	void setLostNotifySendTask(bool state);
	void setLostNotifyRecTask(bool state);



	event void leaderGenerator.fired()
	{	
		//dbg("SRTreeC", "mphka sthn leaderGenerator:%d\n\n",TOS_NODE_ID);



		 if(iwasLeader==FALSE)
		 {
		 	double leader = (double) ((rand())/(double)RAND_MAX);
		 	double tn =0.25/1-0.25*(roundCounter%4);
		 	//dbg("SRTreeC", "the propability:%f  with tn=%f\n\n",leader,tn);

		 	if(leader<tn)
		 	{
		 		imLeader=TRUE;
		 		iwasLeader=TRUE;
		 		//dbg("SRTreeC", "the propability:%f  with tn=%f node: %d\n\n",leader,tn,TOS_NODE_ID);;
		 	}
			else
			{
				imLeader=FALSE;
			}

			if(TOS_NODE_ID==0)
			{
				imLeader=TRUE;
			}

		 }

		 call leaderGenerator.startOneShot(TIMER_PERIOD_MILLI);
		
	}




	event void valueGenerator.fired()     // generate some random value for the node
	{
		
		value = rand()%41 + TOS_NODE_ID;
		//dbg("SRTreeC", "TOS_NODE_ID: %d with value:%d\n",TOS_NODE_ID,value);
		call valueGenerator.startOneShot(valueTimer);   //   declare value timer
		return;
	}




	event void NotifyParentMsgTimer.fired() 	
	{
		post NotifyParentMsgTask();        
	}




		event void Boot.booted()
	{
		call RadioControl.start();
		
		setRoutingSendBusy(FALSE);
		setNotifySendBusy(FALSE);



			atomic
		{
			// na paroyme thn timh apo valueGenerator
			call valueGenerator.startOneShot(TIMER_FAST_PERIOD);  // initialize node value for the first time
		}


			atomic
		{
			call leaderGenerator.startOneShot(TIMER_FAST_PERIOD);
		}


		roundCounter=0;
		sum=0;              // for avg
		squares=0;		// for variance
		children=1;    // total number of childrens
		srand((unsigned) time(NULL));   //start/initialize the time with randomness
		
									// ena timer na ksekinhsei me mia tyxaiothta
		if(TOS_NODE_ID==0)
		{
			imLeader=TRUE;
			iwasLeader=FALSE;
			parentID=0;
			//dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
		}
		else
		{	
			imLeader=FALSE;
			iwasLeader=FALSE;
			
			parentID=-1;
			//dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
		}
	}



	event void RadioControl.startDone(error_t err)
	{
		if (err == SUCCESS)
		{
			//dbg("Radio" , "Radio initialized successfully!!!\n");

			if (TOS_NODE_ID==0)
			{
				call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
			}
		}
		else
		{
			//dbg("Radio" , "Radio initialization failed! Retrying...\n");
			call RadioControl.start();
		}
	}
	
	event void RadioControl.stopDone(error_t err)
	{ 
		//dbg("Radio", "Radio stopped!\n");
	}







		event void RoutingMsgTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		
		RoutingMsg* mrpkt;
		//dbg("SRTreeC", "RoutingMsgTimer fired!  radioBusy = %s \n",(RoutingSendBusy)?"True":"False");

		if (TOS_NODE_ID==0)
		{
			//roundCounter+=1;
			
			//dbg("SRTreeC", "\n ##################################### \n");
			//dbg("SRTreeC", "#######   ROUND   %u    ############## \n", roundCounter);
			//dbg("SRTreeC", "#####################################\n");
			
			call NotifyParentMsgTimer.startOneShot(TIMER_PERIOD_MILLI); //if you are node 0 call NotifyParentMsgTimer to display avg and variance
			//call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
		}

		
	
		
		
		if(call RoutingSendQueue.full())
		{
			return;
		}


	
		 
		
		
		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		if(mrpkt==NULL)
		{
			//dbg("SRTreeC","RoutingMsgTimer.fired(): No valid payload... \n");
			return;
		}
		atomic{
		mrpkt->senderID=TOS_NODE_ID;
		}
		//dbg("SRTreeC" , "Sending RoutingMsg... \n");

	
		

		if( imLeader==TRUE && iwasLeader==TRUE )
		{
			call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR); // send broadcast message
			call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
			//dbg("SRTreeC", "I AM BROADCASTING %d \n",TOS_NODE_ID);
			
			enqueueDone=call RoutingSendQueue.enqueue(tmp);
		
			if( enqueueDone==SUCCESS)
			{
				if (call RoutingSendQueue.size()==1)
				{
					//dbg("SRTreeC", "SendTask() posted!!\n");
					post sendRoutingTask();
				}
				
				//dbg("SRTreeC","RoutingMsg enqueued successfully in SendingQueue!!!\n");
			}
			else
			{
				//dbg("SRTreeC","RoutingMsg failed to be enqueued in SendingQueue!!!");
			}		
		}
		else
		{
			//call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
		}	
		
	}


	task void sendRoutingTask()
	{
		//uint8_t skip;
		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;
		//message_t radioRoutingSendPkt;
		


		if (call RoutingSendQueue.empty())
		{
			//dbg("SRTreeC","sendRoutingTask(): Q is empty!\n");
			return;
		}
		
		
		if(RoutingSendBusy)
		{
			//dbg("SRTreeC","sendRoutingTask(): RoutingSendBusy= TRUE!!!\n");
			setLostRoutingSendTask(TRUE);
			return;
		}
		
		radioRoutingSendPkt = call RoutingSendQueue.dequeue();
	
		mlen= call RoutingPacket.payloadLength(&radioRoutingSendPkt);
		mdest=call RoutingAMPacket.destination(&radioRoutingSendPkt);
		if(mlen!=sizeof(RoutingMsg))
		{
			//dbg("SRTreeC","\t\tsendRoutingTask(): Unknown message!!!\n");
			return;
		}
		sendDone=call RoutingAMSend.send(mdest,&radioRoutingSendPkt,mlen);
		
		if ( sendDone== SUCCESS)
		{
			//dbg("SRTreeC","sendRoutingTask(): Send returned success!!!\n");
			setRoutingSendBusy(TRUE);
		}
		else
		{
			//dbg("SRTreeC","send failed!!!\n");
			//setRoutingSendBusy(FALSE);
		}
	}







	//	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len)

	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
	
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource =call RoutingAMPacket.source(msg);
		
		//dbg("SRTreeC", "### RoutingReceive.receive() start ##### \n");
		//dbg("SRTreeC", "Something received!!!  from %u to  %d \n",((RoutingMsg*) payload)->senderID ,  TOS_NODE_ID);

		
		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		//tmp=*(message_t*)msg;
		}
		enqueueDone=call RoutingReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
			post receiveRoutingTask();
		}
		else
		{
			//dbg("SRTreeC","RoutingMsg enqueue failed!!! \n");			
		}
		
		
		//dbg("SRTreeC", "### RoutingReceive.receive() end ##### \n");
		return msg;
	}


		task void receiveRoutingTask()
	{
		message_t tmp;
		uint8_t len;
		message_t radioRoutingRecPkt;
		

		radioRoutingRecPkt= call RoutingReceiveQueue.dequeue();
		
		len= call RoutingPacket.payloadLength(&radioRoutingRecPkt);
		
		//dbg("SRTreeC","ReceiveRoutingTask(): len=%u \n",len);

		// processing of radioRecPkt
		
		// pos tha xexorizo ta 2 diaforetika minimata???
				
		if(len == sizeof(RoutingMsg))
		{

			RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt,len));
			
			
			//dbg("SRTreeC" , "receiveRoutingTask():from senderID= %d to %d \n", mpkt->senderID , TOS_NODE_ID );


			if(imLeader==FALSE){
				if ( (parentID<0)||(parentID>=65535))
				{	
					// tote den exei akoma patera
					parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;q
					
					//dbg("SRTreeC","I received a message from Leader :%d and i am %d\n",parentID,TOS_NODE_ID);

					call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
					call NotifyParentMsgTimer.startOneShot(roundCounter*TIMER_PERIOD_MILLI +routingTime+rand()%60);  // listening  > TIMER_FAST_PERIOD
					// proper time to "wake up" the node to process data from his children
						
				} 
				else{
					double newparentprob = (double) ((rand())/(double)RAND_MAX);
					double tn =0.2/1-0.2*(roundCounter%5);
					
					if(newparentprob<tn)
					{
						parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;q
						call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);

					}
				}
			}
			else
			{	 
				call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
				call NotifyParentMsgTimer.startOneShot(roundCounter*TIMER_PERIOD_MILLI +routingTime +200+ rand()%60);
			}
		}
		//call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);

	}




	
	event void RoutingAMSend.sendDone(message_t * msg , error_t err)
	{
		//dbg("SRTreeC", "A Routing package sent... %s \n",(err==SUCCESS)?"True":"False");
		
		//dbg("SRTreeC" , "Package sent %s \n", (err==SUCCESS)?"True":"False");

		setRoutingSendBusy(FALSE);
		
		if(!(call RoutingSendQueue.empty()))
		{
			post sendRoutingTask();
		}
		else
		{
			
		}
	
		
	}



	task void NotifyParentMsgTask()
	{
		message_t tmp;
		sum+=value ;
		squares+=value*value;


		if(TOS_NODE_ID==0)
		{


			
			dbg("SRTreeC", "\n ##################################### \n");
			dbg("SRTreeC", "#######   ROUND   %u    ############## \n", roundCounter);
			dbg("SRTreeC", "#####################################\n");

			dbg("SRTreeC", "sum   %d   \n", sum);

				
		

			avg= (double)sum/(double)children;
			variance= (double)squares/(double)children - avg*avg;

			dbg("SRTreeC","Average is:%f\n",avg);
			dbg("SRTreeC","Variance is:%f\n",variance);
			dbg("SRTreeC","ROUND is:%u \n",roundCounter);
			dbg("SRTreeC","children is:%d \n\n\n\n", children);

			roundCounter+=1;
			sum=0;                    //reset elements for the id = 0 so he can proccess new  data
			squares=0;
			children=1;


		


			call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);

		}
		else   // prepare message to send to the parent
		{	
			

			NotifyParentMsg* m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
			if(parentID==-1)
			{	
				imLeader=TRUE;
				iwasLeader=FALSE;
				parentID=0;
			}


			roundCounter+=1;

			if(imLeader==TRUE && iwasLeader==TRUE)
			{
				parentID=0;
			}

			m->senderID=TOS_NODE_ID;
			m->parentID=parentID;   // from receiveRouting
			m->sum      = sum;
			m->squares  = squares;
			m->average = avg;
			m->variance = variance;	
			m->children=children;
		


			//dbg("SRTreeC","NODE :%d WITH  VALUE:%u  sending to his father:%d\n", TOS_NODE_ID,value,parentID);
			


			call NotifyAMPacket.setDestination(&tmp, parentID);  //unicast message send
			call NotifyPacket.setPayloadLength(&tmp,sizeof(NotifyParentMsg));

			if (call NotifySendQueue.enqueue(tmp)==SUCCESS)
			{
				//dbg("SRTreeC", "NotifyParentMsg Succefull in SendingQueue\n");
				post sendNotifyTask();
			}

			sumOld = m->sum ;
			//squaresOld =m->squares ;
			//childrenOld =m ->children ;
		

		}


	

		call NotifyParentMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
		
	}





		task void sendNotifyTask()
	{
		uint8_t mlen;//, skip;
		error_t sendDone;
		uint16_t mdest;
		NotifyParentMsg* mpayload;
		
		//message_t radioNotifySendPkt;
		

		if (call NotifySendQueue.empty())
		{
			//dbg("SRTreeC","sendNotifyTask(): Q is empty!\n");
			return;
		}
		
		if(NotifySendBusy==TRUE)
		{
			//dbg("SRTreeC","sendNotifyTask(): NotifySendBusy= TRUE!!!\n");
			setLostNotifySendTask(TRUE);
			return;
		}
		
		radioNotifySendPkt = call NotifySendQueue.dequeue();
		

		mlen=call NotifyPacket.payloadLength(&radioNotifySendPkt);
		
		mpayload= call NotifyPacket.getPayload(&radioNotifySendPkt,mlen);
		
		if(mlen!= sizeof(NotifyParentMsg))
		{
			//dbg("SRTreeC", "\t\t sendNotifyTask(): Unknown message!!\n");
			return;
		}
		
		//dbg("SRTreeC" , " sendNotifyTask(): mlen = %u  senderID= %u \n",mlen,mpayload->senderID);
		mdest= call NotifyAMPacket.destination(&radioNotifySendPkt);
		
		
		sendDone=call NotifyAMSend.send(mdest,&radioNotifySendPkt, mlen);
		
		if ( sendDone== SUCCESS)
		{
			//dbg("SRTreeC","sendNotifyTask(): Send returned success!!!\n");
			setNotifySendBusy(TRUE);
		}
		else
		{
			//dbg("SRTreeC","send failed!!!\n");
			//setNotifySendBusy(FALSE);
		}
	}






	event message_t* NotifyReceive.receive( message_t* msg , void* payload , uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource = call NotifyAMPacket.source(msg);
		
		//dbg("SRTreeC", "### NotifyReceive.receive() start ##### \n");
		//dbg("SRTreeC", "Something received!!!  from %u to  %d \n",((NotifyParentMsg*) payload)->senderID, TOS_NODE_ID);


		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		//tmp=*(message_t*)msg;
		}
		enqueueDone=call NotifyReceiveQueue.enqueue(tmp);
		
		if( enqueueDone== SUCCESS)
		{
			post receiveNotifyTask();
		}
		else
		{
			//dbg("SRTreeC","NotifyMsg enqueue failed!!! \n");			
		}
		
		//call Leds.led1Off();
		//dbg("SRTreeC", "### NotifyReceive.receive() end ##### \n");
		return msg;
	}




	task void receiveNotifyTask()
	{
		message_t tmp;
		uint8_t len;
		message_t radioNotifyRecPkt;
		

		radioNotifyRecPkt= call NotifyReceiveQueue.dequeue();
		
		len= call NotifyPacket.payloadLength(&radioNotifyRecPkt);
		
		//dbg("SRTreeC","ReceiveNotifyTask(): len=%u \n",len);

		if(len == sizeof(NotifyParentMsg))
		{
			// an to parentID== TOS_NODE_ID tote
			// tha proothei to minima pros tin riza xoris broadcast
			// kai tha ananeonei ton tyxon pinaka paidion..
			// allios tha diagrafei to paidi apo ton pinaka paidion
			
			NotifyParentMsg* mr = (NotifyParentMsg*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));
			
			

			if(imLeader==TRUE && iwasLeader==TRUE){
				//dbg("SRTreeC" , "NotifyParentMsg received from %d sending to %d !!! \n", mr->senderID,TOS_NODE_ID);
				//dbg("SRTreeC" , "I am leader:%d\n",TOS_NODE_ID);
			}

			
		

			if ( mr->parentID == TOS_NODE_ID) // "im the father of the sender's id"
			{	

				//dbg("SRTreeC", "%d received sum:%d from TOS_NODE_ID:%d\n\n",TOS_NODE_ID,mr->sum,mr->senderID);
				sum += mr->sum;
				squares +=mr ->squares;
				children+=mr->children;
				//dbg("SRTreeC", "Sum : %d children:%d node:%d \n",sum,children,TOS_NODE_ID);
				
				avg= (double)sum/(double)children;
				variance= (double)squares/(double)children - avg*avg;
				

			}


			
		}
		else
		{
			//dbg("SRTreeC","receiveNotifyTask():Empty message!!! \n");
			setLostNotifyRecTask(TRUE);
			return;
		}
		
	}
	





	event void NotifyAMSend.sendDone(message_t *msg , error_t err)
	{
		//dbg("SRTreeC", "A Notify package sent... %s \n",(err==SUCCESS)?"True":"False");
		
	
		//dbg("SRTreeC" , "Package sent %s \n", (err==SUCCESS)?"True":"False");
		setNotifySendBusy(FALSE);
		
		if(!(call NotifySendQueue.empty()))
		{
			post sendNotifyTask();
		}
		else
		{

			children=1;
			sum=0;
			squares=0;
			parentID=-1;
			if(roundCounter%4==0)
			{
				//dbg("SRTreeC" , "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n",roundCounter);
				//dbg("SRTreeC" , "Reset leader:%d in round:%u\n",TOS_NODE_ID,roundCounter);
				imLeader=FALSE;
				iwasLeader=FALSE;
			}
		}
		// ti prepei na ginei otan stelnetai to paketo?

		
		
	}




	
	void setLostRoutingSendTask(bool state)
	{
		atomic{
			lostRoutingSendTask=state;
		}
	}
	
	void setLostNotifySendTask(bool state)
	{
		atomic{
		lostNotifySendTask=state;
		}
	}
	
	void setLostNotifyRecTask(bool state)
	{
		atomic{
		lostNotifyRecTask=state;
		}
	}
	
	void setLostRoutingRecTask(bool state)
	{
		atomic{
		lostRoutingRecTask=state;
		}
	}
	void setRoutingSendBusy(bool state)
	{
		atomic{
		RoutingSendBusy=state;
		}
	}
	
	void setNotifySendBusy(bool state)
	{
		atomic{
		NotifySendBusy=state;
		}
		//dbg("SRTreeC","NotifySendBusy = %s\n", (state == TRUE)?"TRUE":"FALSE");
	}





	
	
	
	
	event void LostTaskTimer.fired()
	{
		if (lostRoutingSendTask)
		{
			post sendRoutingTask();
			setLostRoutingSendTask(FALSE);
		}
		
		if( lostNotifySendTask)
		{
			post sendNotifyTask();
			setLostNotifySendTask(FALSE);
		}
		
		if (lostRoutingRecTask)
		{
			post receiveRoutingTask();
			setLostRoutingRecTask(FALSE);
		}
		
		if ( lostNotifyRecTask)
		{
			post receiveNotifyTask();
			setLostNotifyRecTask(FALSE);
		}
	}
	

	
	
	

}
	

	
	 
	