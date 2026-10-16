"""meal slot on logs, chat message meta, heart rate on bp readings, medical records

Revision ID: a1c3e5b7d902
Revises: e9b1d3f5a7c9
Create Date: 2026-10-16 18:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = 'a1c3e5b7d902'
down_revision: Union[str, Sequence[str], None] = 'e9b1d3f5a7c9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('logs', sa.Column('meal_slot', sa.Text(), nullable=True))
    op.add_column('logs', sa.Column('slot_confirmed', sa.Boolean(), server_default=sa.text('true'), nullable=False))
    op.add_column('messages', sa.Column('meta', postgresql.JSONB(astext_type=sa.Text()), nullable=True))
    op.create_index('ix_messages_user_created', 'messages', ['user_id', sa.text('created_at DESC')])
    op.add_column('bp_readings', sa.Column('pulse', sa.Integer(), nullable=True))
    op.create_table(
        'medical_records',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('kind', sa.Text(), nullable=False),
        sa.Column('title', sa.Text(), nullable=False),
        sa.Column('recorded_on', sa.Date(), nullable=False),
        sa.Column('provider', sa.Text(), nullable=True),
        sa.Column('details', sa.Text(), nullable=True),
        sa.Column('values', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column('source', sa.Text(), server_default='manual', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_medical_records_user_date', 'medical_records', ['user_id', sa.text('recorded_on DESC')])


def downgrade() -> None:
    op.drop_index('ix_medical_records_user_date', table_name='medical_records')
    op.drop_table('medical_records')
    op.drop_column('bp_readings', 'pulse')
    op.drop_index('ix_messages_user_created', table_name='messages')
    op.drop_column('messages', 'meta')
    op.drop_column('logs', 'slot_confirmed')
    op.drop_column('logs', 'meal_slot')
