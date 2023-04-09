#include "SimpleRoutingTree.h"
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
}
implementation
{
	nodesStruct nodes[maxchildren];
	
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

	event void valueGenerator.fired()     // generate some random value for the node
	{
		value = rand()%41 + TOS_NODE_ID;
		call valueGenerator.startOneShot(valueTimer);   //   declare value timer
		return;
	}




	event void NotifyParentMsgTimer.fired() 	
	{
		post NotifyParentMsgTask();        
	}




		event void Boot.booted()
	{
		/////// arxikopoiisi radio kai serial
		call RadioControl.start();
		
		setRoutingSendBusy(FALSE);
		setNotifySendBusy(FALSE);

		roundCounter=0;
		sum=0;              // for avg
		squares=0;		// for variance
		children=0;    // total number of childrens
		srand((unsigned) time(NULL));   //start/initialize the time with randomness
		
									// ena timer na ksekinhsei me mia tyxaiothta
		if(TOS_NODE_ID==0)
		{
			curdepth=0;
			parentID=0;
			//dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
		}
		else
		{
			curdepth=-1;
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
				call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
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
			roundCounter+=1;
			
			//dbg("SRTreeC", "\n ##################################### \n");
			//dbg("SRTreeC", "#######   ROUND   %u    ############## \n", roundCounter);
			//dbg("SRTreeC", "#####################################\n");
			
			call NotifyParentMsgTimer.startOneShot(TIMER_PERIOD_MILLI); //if you are node 0 call NotifyParentMsgTimer to display avg and variance
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
		mrpkt->depth = curdepth;
		}
		//dbg("SRTreeC" , "Sending RoutingMsg... \n");
		
		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR); // send broadcast message
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		
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








	task void sendRoutingTask()
	{
		//uint8_t skip;
		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;
		//message_t radioRoutingSendPkt;
		

			// na paroyme thn timh apo valueGenerator
		call valueGenerator.startOneShot(TIMER_FAST_PERIOD);  // initialize node value for the first time
		


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
			
			//if(TOS_NODE_ID >0)
			//{
				//call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
			//}
			//
			
			//dbg("SRTreeC" , "receiveRoutingTask():senderID= %d , depth= %d \n", mpkt->senderID , mpkt->depth);

			if ( (parentID<0)||(parentID>=65535))
			{
				// tote den exei akoma patera
				parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;q
				curdepth= mpkt->depth + 1;

					call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);

					call NotifyParentMsgTimer.startOneShot(routingTime + (maxNodes - curdepth)*TIMER_FAST_PERIOD - (listeningNotifyMsgTime*(curdepth+1))  + rand()%60);  // listening  > TIMER_FAST_PERIOD
			} // proper time to "wake up" the node to process data from his children
		}
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
	
		
	}



	task void NotifyParentMsgTask()
	{
		message_t tmp;
		int tempSum=value ;
		int tempSquares=value*value;

		

		int tempChildren=1;
		double avg = 0;
		double variance = 0;	

		if(TOS_NODE_ID==0)
		{


			
			dbg("SRTreeC", "\n ##################################### \n");
			dbg("SRTreeC", "#######   ROUND   %u    ############## \n", roundCounter);
			dbg("SRTreeC", "#####################################\n");

			
				
			for( i=0;i<nodeChildren; i++)
			{
				if(nodes[i].success==1)    // take the new values if they exist
				{
					sum+=nodes[i].sum;
					squares+=nodes[i].squares;
					children+=nodes[i].children;
				}
				else                    // else take the old ones
				{
					sum+=nodes[i].sumOld;
					squares+=nodes[i].squaresOld;
					children+=nodes[i].childrenOld;
				}
			}

			avg= (double)sum/(double)children;
			variance= (double)squares/(double)children - avg*avg;

			dbg("SRTreeC","Average is:%f\n",avg);
			dbg("SRTreeC","Variance is:%f\n",variance);
			dbg("SRTreeC","ROUND is:%u \n",roundCounter);
			dbg("SRTreeC","children is:%d \n\n\n\n", children);

			roundCounter+=1;
			sum=0;                    //reset elements for the id = 0 so he can proccess new  data
			squares=0;
			children=0;


			

		}
		else   // prepare message to send to the parent
		{	

			NotifyParentMsg* m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
			m->senderID=TOS_NODE_ID;
			m->parentID=parentID;   // from receiveRouting
			
			

			for( i = 0;i<nodeChildren;i++)
			{
				if(nodes[i].success==1)
				{
					tempSum      +=  nodes[i].sum;
					tempSquares  +=  nodes[i].squares;
					tempChildren +=  nodes[i].children;
				}
				else
				{
					tempSum      +=  nodes[i].sumOld;               // prepare notifyparent message with the proper values
					tempSquares  +=  nodes[i].squaresOld;
					tempChildren +=  nodes[i].childrenOld;
				}
				
			}

			m->sum      = tempSum;
			m->squares  = tempSquares;
			m->children = tempChildren;
			//dbg("SRTreeC","NODE : %d WITH  VALUE IS %u \n", TOS_NODE_ID,value);
			
			if (!(sumOld == m->sum)  || m->sum<0  )  // if sum didnt change we should not send the message
			{
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
		


			for( i=0; i<nodeChildren;i++)
			{
				nodes[i].success  = 0;   // reset the success of each childer so they can "hear" new values
			}

			

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
			
			//dbg("SRTreeC" , "NotifyParentMsg received from %d !!! \n", mr->senderID);

			if ( mr->parentID == TOS_NODE_ID) // "im the father of the sender's id"
			{	
				for( i=0;i<nodeChildren;i++)
				{
					if(nodes[i].senderID == mr->senderID)  // if children already exists 
					{
						nodes[i].sum=mr->sum;
						nodes[i].squares=mr->squares;
						nodes[i].success=1;
						nodes[i].children=mr->children;
							nodes[i].sumOld      = nodes[i].sum;         // store the old values in case we will lose messages
							nodes[i].squaresOld  = nodes[i].squares;
							//nodes[i].success     = 0;
							nodes[i].childrenOld = nodes[i].children;
						break;
					}
				}

				if(i==nodeChildren) // else add the sender as your children
				{
					nodes[i].senderID=mr->senderID;
					nodes[i].sum=mr->sum;
					nodes[i].squares=mr->squares;
					nodes[i].success=1;
					nodes[i].children=mr->children;
						nodes[i].sumOld      = nodes[i].sum;   ///store the old values in case we will lose messages
						nodes[i].squaresOld  = nodes[i].squares;
						//nodes[i].success     = 0;
						nodes[i].childrenOld = nodes[i].children;
					nodeChildren++;
				}
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
			//reset for new round
			children=0;
			sum=0;
			squares=0;
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
	

	
	 
	