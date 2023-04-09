#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H


enum{
	SENDER_QUEUE_SIZE=5,
	RECEIVER_QUEUE_SIZE=3,
	AM_SIMPLEROUTINGTREEMSG=22,
	AM_ROUTINGMSG=22,
	AM_NOTIFYPARENTMSG=12,
	SEND_CHECK_MILLIS=70*1024,
	TIMER_PERIOD_MILLI=30*1024,
	TIMER_FAST_PERIOD=205,
	listeningNotifyMsgTime=220,
	routingTime = 100*1024,
	valueTimer=30*1024,
	maxNodes = 25,   
	maxchildren = 8,

};
/*uint16_t AM_ROUTINGMSG=AM_SIMPLEROUTINGTREEMSG;
uint16_t AM_NOTIFYPARENTMSG=AM_SIMPLEROUTINGTREEMSG;
*/
typedef nx_struct RoutingMsg
{
	nx_uint16_t senderID;
	nx_uint8_t depth;
} RoutingMsg;

typedef nx_struct NotifyParentMsg
{
	nx_uint16_t senderID;
	nx_uint16_t parentID;
	nx_uint16_t sum;
	nx_uint16_t squares;
	nx_uint16_t children;
	
	nx_uint32_t average;
	nx_uint32_t variance;

	nx_uint8_t depth;
} NotifyParentMsg;


typedef nx_struct nodesStruct
{
	nx_uint16_t senderID;
	nx_uint16_t squares;
	nx_uint16_t squaresOld;
	nx_uint16_t sum;
	nx_uint16_t sumOld;
	nx_uint16_t children;
	nx_uint16_t childrenOld;
	nx_uint8_t success;
}nodesStruct;

#endif
