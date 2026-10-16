"""plan preferences and overrides

Revision ID: e9b1d3f5a7c9
Revises: d7f9b1c3e5a7
Create Date: 2026-10-16 09:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'e9b1d3f5a7c9'
down_revision: Union[str, Sequence[str], None] = 'd7f9b1c3e5a7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'plan_preferences',
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('wake_time', sa.Text(), server_default='06:00', nullable=False),
        sa.Column('meal_times', postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.Column('exercise_time', sa.Text(), server_default='17:00', nullable=False),
        sa.Column('exercise_days', postgresql.ARRAY(sa.SmallInteger()), server_default=sa.text("'{0,1,2,3,4}'"), nullable=False),
        sa.Column('exercise_kinds', postgresql.ARRAY(sa.Text()), server_default=sa.text("'{jalan cepat}'"), nullable=False),
        sa.Column('strength_days', sa.Integer(), server_default='0', nullable=False),
        sa.Column('goal', sa.Text(), server_default='jaga', nullable=False),
        sa.Column('channels', postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text('\'{"app": true, "whatsapp": false}\'::jsonb'), nullable=False),
        sa.Column('reminders', postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.Column('quiet_hours', postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text('\'{"start": "21:30", "end": "06:00"}\'::jsonb'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('user_id'),
    )
    # Penggantian manual satu usulan ("ganti usulan"): replacement = {"offset": n} -> alternatif ke-n yang pas anggaran.
    op.create_table(
        'plan_overrides',
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('date', sa.Date(), nullable=False),
        sa.Column('slot', sa.Text(), nullable=False),
        sa.Column('replacement', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('user_id', 'date', 'slot'),
    )


def downgrade() -> None:
    op.drop_table('plan_overrides')
    op.drop_table('plan_preferences')
